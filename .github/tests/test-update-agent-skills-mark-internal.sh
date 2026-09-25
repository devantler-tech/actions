#!/usr/bin/env bash
# Contract test for update-agent-skills/mark-internal.sh: every SKILL.md under a directory ends up
# with `metadata.internal: true`, the body and the rest of the frontmatter are preserved, an already
# tagged file is not rewritten, and a malformed frontmatter fails instead of being skipped.
# shellcheck disable=SC2016 # the wiring assertions compare literal ${{ }} and ${VAR} strings on purpose
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$repo_root/update-agent-skills/mark-internal.sh"
fixture="$repo_root/.github/tests/agent-skills-fixtures/pinned-self-improvement/SKILL.md"

fail() {
  echo "::error::$*"
  exit 1
}

[[ -f "$script" ]] || fail "missing $script"
command -v yq >/dev/null 2>&1 || fail "yq is required to run this test"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A supported yq may print much more help than a pipe buffer. Its capability
# probe must finish reading the producer, and must still reject a failed producer
# even when its partial output already contains the capability name.
mkdir -p "$work/help-bin" "$work/empty"
cat > "$work/help-bin/yq" <<'YQ'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != --help ]]; then exec "$REAL_YQ" "$@"; fi
case "$HELP_CASE" in
  short) printf '%s\n' '--front-matter' ;;
  long)
    printf '%s\n' '--front-matter'
    for ((i=0; i<4096; i++)); do printf '%1024s\n' ''; done
    ;;
  missing) printf '%s\n' 'unrelated help' ;;
  failed) printf '%s\n' '--front-matter'; exit 42 ;;
esac
YQ
chmod +x "$work/help-bin/yq"
real_yq=$(command -v yq)
for help_case in short long missing failed; do
  rc=0
  PATH="$work/help-bin:$PATH" REAL_YQ="$real_yq" HELP_CASE="$help_case" \
    bash "$script" "$work/empty" > "$work/help-$help_case.log" 2>&1 || rc=$?
  case "$help_case" in
    short|long) [[ "$rc" == 0 ]] || fail "$help_case successful yq help was rejected" ;;
    missing|failed)
      [[ "$rc" != 0 ]] || fail "$help_case yq help was accepted"
      grep -qF 'yq v4 with --front-matter support is required' "$work/help-$help_case.log" ||
        fail "$help_case yq help failed for an unrelated reason"
      ;;
  esac
done

body_of() { awk 'n>=2{print} /^---$/{n++}' "$1"; }
internal_of() { yq --front-matter=extract '.metadata.internal' "$1"; }

# ── Layout: standard, nested plugin, pre-tagged, explicit false, no metadata, no frontmatter ──
root="$work/skills"
mkdir -p "$root/untagged" "$root/tagged" "$root/false" "$root/no-metadata" "$root/no-frontmatter" \
  "$work/plugins/p/skills/nested"
cp "$fixture" "$root/untagged/SKILL.md"
cp "$fixture" "$work/plugins/p/skills/nested/SKILL.md"
# The extra spaces are formatting yq normalises on any rewrite, so this file stays byte-identical only
# if an already tagged skill is genuinely skipped.
cat >"$root/tagged/SKILL.md" <<'EOF'
---
name: tagged
description:   Already internal.
metadata:
    github-repo: https://github.com/devantler-tech/agent-skills
    internal: true
---
# Tagged
EOF
cat >"$root/false/SKILL.md" <<'EOF'
---
name: explicit-false
description: Explicitly public.
metadata:
    internal: false
---
# False

---
A thematic break in the body must survive.
EOF
cat >"$root/no-metadata/SKILL.md" <<'EOF'
---
name: no-metadata
description: No metadata mapping.
---
# No metadata
EOF
printf '# Not a skill\n\nNo frontmatter here.\n' >"$root/no-frontmatter/SKILL.md"

tagged_before=$(shasum -a 256 "$root/tagged/SKILL.md" | awk '{print $1}')
nofm_before=$(shasum -a 256 "$root/no-frontmatter/SKILL.md" | awk '{print $1}')
false_body_before=$(body_of "$root/false/SKILL.md")
untagged_body_before=$(body_of "$root/untagged/SKILL.md")

out=$(bash "$script" "$root" 2>&1) || fail "script failed on a valid tree: $out"

for skill in untagged false no-metadata tagged; do
  [[ "$(internal_of "$root/$skill/SKILL.md")" == "true" ]] ||
    fail "$skill: expected metadata.internal=true, got $(internal_of "$root/$skill/SKILL.md")"
done

[[ "$(shasum -a 256 "$root/tagged/SKILL.md" | awk '{print $1}')" == "$tagged_before" ]] ||
  fail "an already tagged SKILL.md was rewritten"
[[ "$(shasum -a 256 "$root/no-frontmatter/SKILL.md" | awk '{print $1}')" == "$nofm_before" ]] ||
  fail "a SKILL.md without frontmatter was modified"
[[ "$out" == *"no-frontmatter/SKILL.md"* ]] ||
  fail "skipping a SKILL.md without frontmatter must be reported: $out"

[[ "$(body_of "$root/untagged/SKILL.md")" == "$untagged_body_before" ]] || fail "untagged: body changed"
[[ "$(body_of "$root/false/SKILL.md")" == "$false_body_before" ]] || fail "false: body changed"

for key in github-path github-pinned github-ref github-repo github-tree-sha; do
  want=$(yq --front-matter=extract ".metadata.\"$key\"" "$fixture")
  got=$(yq --front-matter=extract ".metadata.\"$key\"" "$root/untagged/SKILL.md")
  [[ "$want" == "$got" ]] || fail "untagged: metadata.$key changed ($want -> $got)"
done
for key in name description license; do
  [[ "$(yq --front-matter=extract ".$key" "$fixture")" == "$(yq --front-matter=extract ".$key" "$root/untagged/SKILL.md")" ]] ||
    fail "untagged: $key changed"
done
grep -q '^    internal: true$' "$root/untagged/SKILL.md" ||
  fail "untagged: expected the existing 4-space metadata indentation to be kept"

# Only the root passed in is walked.
if [[ "$(internal_of "$work/plugins/p/skills/nested/SKILL.md")" == "true" ]]; then
  fail "a SKILL.md outside the requested directory was tagged"
fi

# Nested plugin layout under the requested directory is covered.
bash "$script" "$work/plugins" >/dev/null 2>&1 || fail "script failed on a nested plugin layout"
[[ "$(internal_of "$work/plugins/p/skills/nested/SKILL.md")" == "true" ]] || fail "nested: not tagged"

# Idempotent: a second pass rewrites nothing.
snapshot() { find "$1" -type f -name SKILL.md -print0 | sort -z | xargs -0 shasum -a 256; }
first=$(snapshot "$root")
bash "$script" "$root" >/dev/null 2>&1 || fail "second pass failed"
[[ "$(snapshot "$root")" == "$first" ]] || fail "second pass modified an already tagged tree"

# Malformed frontmatter fails closed rather than leaving the skill discoverable.
bad="$work/bad"
mkdir -p "$bad/broken"
printf -- '---\nname: broken\nmetadata: [unclosed\n---\n# Broken\n' >"$bad/broken/SKILL.md"
if bash "$script" "$bad" >/dev/null 2>&1; then
  fail "malformed frontmatter must fail"
fi

# A missing directory fails.
if bash "$script" "$work/does-not-exist" >/dev/null 2>&1; then
  fail "a missing directory must fail"
fi

# ── Wiring: the input reaches the script from both entrypoints ──
# An enabled reusable-workflow run opens a real update pull request, so CI cannot exercise that path;
# these assertions pin the forwarding it depends on instead, and the enabled action job covers the rest.
action="$repo_root/update-agent-skills/action.yaml"
workflow="$repo_root/.github/workflows/update-agent-skills.yaml"

[[ "$(yq -r '.inputs."mark-internal".default' "$action")" == "false" ]] ||
  fail "action input mark-internal must default to \"false\""
[[ "$(yq -r '.runs.steps[] | select(.id == "update") | .env.INPUT_MARK_INTERNAL' "$action")" == '${{ inputs.mark-internal }}' ]] ||
  fail "action update step must receive mark-internal as INPUT_MARK_INTERNAL"
update_run=$(yq -r '.runs.steps[] | select(.id == "update") | .run' "$action") ||
  fail "cannot read the action update step"
grep -qF '${GITHUB_ACTION_PATH}/mark-internal.sh' <<< "$update_run" ||
  fail "action update step must invoke mark-internal.sh"

[[ "$(yq -r '.on.workflow_call.inputs."mark-internal".type' "$workflow")" == "boolean" ]] ||
  fail "reusable workflow input mark-internal must be a boolean"
[[ "$(yq -r '.on.workflow_call.inputs."mark-internal".default' "$workflow")" == "false" ]] ||
  fail "reusable workflow input mark-internal must default to false"
forwarded=$(yq -r '.jobs."update-agent-skills".steps[] | select(.uses == "./.devantler-tech-actions/update-agent-skills") | .with."mark-internal"' "$workflow")
[[ "$forwarded" == '${{ inputs.mark-internal }}' ]] ||
  fail "reusable workflow must forward mark-internal to update-agent-skills (got: $forwarded)"

echo "mark-internal contract: all assertions passed"
