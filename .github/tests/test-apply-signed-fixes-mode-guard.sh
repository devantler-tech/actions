#!/usr/bin/env bash

# `createCommitOnBranch`'s FileAddition carries a path and its contents and nothing else, so a
# file mode cannot be SET through it. It IS inherited from the base tree. Measured 2026-08-24
# against devantler-tech/actions:
#
#   * modifying a path already at 100755 -> stayed 100755, commit verified=true
#   * adding a NEW executable file       -> landed at 100644, the bit silently dropped
#
# So the safe test is "would this commit change the file's mode", not "is this file executable".
# The difference is not academic: rejecting every executable file rejects the common case (a
# formatter rewriting an existing `.sh` -- 66 such files in platform, 48 in ksail, 30 here) and
# fails the job for a change the API handles correctly.
#
# This exercises the workflow's OWN classification text against real git fixtures, rather than a
# copy of it: the block is extracted from the workflow by yq and its stable markers, so an edit
# to the workflow that breaks the rule fails here instead of drifting away from a duplicated
# assertion.

set -euo pipefail

workflow="${1:-.github/workflows/apply-signed-fixes.yaml}"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"

run_block="$(
  yq -r '.jobs["apply-fixes"].steps[] | select(.name == "📤 Commit the applied fixes") | .run' "$workflow"
)"
[[ -n "$run_block" && "$run_block" != "null" ]] ||
  fail "could not extract the commit step's run block from $workflow"

# Pull just the mode classification: from the regular-file guard up to (not including) the
# content encoding. NOTE the end marker is the content-encoding comment, not a closing `fi` at a
# fixed indent -- yq strips the YAML block indentation, so an indent-anchored marker silently
# fails to match and the extraction runs to end-of-file, dragging in the whole commit path.
# shellcheck disable=SC2016  # `$entry_path` is matched LITERALLY in the workflow text; expanding it here would search for this shell's (empty) variable instead.
guard="$(sed -n '/if \[ -L "\$entry_path" \]/,/# File content must never reach argv/p' <<<"$run_block" | sed '$d')"
grep -q 'ls-tree' <<<"$guard" ||
  fail "extracted guard does not consult the base tree; it is not the mode-aware guard this test exists for"
grep -q 'wanted_mode' <<<"$guard" ||
  fail "extracted guard has no wanted_mode computation; extraction markers have drifted"
grep -q 'createCommitOnBranch' <<<"$guard" &&
  fail "extraction over-ran into the commit path; the end marker has drifted"
[[ "$(wc -l <<<"$guard")" -lt 25 ]] ||
  fail "extracted guard is $(wc -l <<<"$guard") lines, far larger than the classification block; extraction has drifted"

# classify <repo> <path> -> exits 0 accept, 1 reject
classify() {
  local repo="$1" entry_path="$2"
  ( cd "$repo" && eval "$(cat <<EOF
set -e
entry_path='$entry_path'
$guard
EOF
)" ) >/dev/null 2>&1
}

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
git -C "$fixture" config user.email t@t; git -C "$fixture" config user.name t
printf 'a\n' > "$fixture/plain.sh";  chmod 644 "$fixture/plain.sh"
printf 'a\n' > "$fixture/exec.sh";   chmod 755 "$fixture/exec.sh"
git -C "$fixture" add -A; git -C "$fixture" commit -qm base

expect() { # <label> <path> <accept|reject>
  local label="$1" path="$2" want="$3"
  if classify "$fixture" "$path"; then got=accept; else got=reject; fi
  [[ "$got" == "$want" ]] || fail "$label: expected $want, got $got"
  echo "  ok  $label -> $got"
}

# 1. the case the old guard wrongly rejected: content edit to an existing executable file
printf 'a\nb\n' > "$fixture/exec.sh"
expect "modified existing executable (mode inherited)" exec.sh accept

# 2. ordinary modification stays fine
printf 'a\nb\n' > "$fixture/plain.sh"
expect "modified existing regular file" plain.sh accept

# 3. a NEW executable file has nothing to inherit -> genuinely unexpressible
printf 'a\n' > "$fixture/new-exec.sh"; chmod 755 "$fixture/new-exec.sh"
expect "new executable file" new-exec.sh reject

# 4. a new ordinary file is expressible
printf 'a\n' > "$fixture/new-plain.sh"; chmod 644 "$fixture/new-plain.sh"
expect "new regular file" new-plain.sh accept

# 5. a mode FLIP on an existing file cannot be expressed either, in either direction
chmod 755 "$fixture/plain.sh"
expect "existing file newly made executable" plain.sh reject
chmod 644 "$fixture/exec.sh"
expect "existing executable file newly made non-executable" exec.sh reject
chmod 755 "$fixture/exec.sh"; chmod 644 "$fixture/plain.sh"

# 6. a symlink is not a regular file
ln -s plain.sh "$fixture/link.sh"
expect "symlink" link.sh reject

echo "PASS: the applied-fixes mode guard rejects exactly the changes the commit API cannot express"
