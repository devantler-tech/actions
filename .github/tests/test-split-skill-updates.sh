#!/usr/bin/env bash

# update-agent-skills' opt-in per-skill mode (#1309) splits one updater run into one patch per
# changed skill, so a skill whose update is blocked strands only itself
# (devantler-tech/agent-plugins#175). This drives the real splitter against a git fixture that
# modifies one skill, adds a file to another, installs a new skill and removes a fourth. It checks
# the manifest, that each patch touches only its own skill and applies cleanly to a fresh checkout,
# that the caller's real index is left alone, and that a change outside every skill fails closed.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
splitter="$repo_root/.github/scripts/split-skill-updates.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$splitter" ]] || fail "split-skill-updates.sh is missing"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

skill() {
  # skill <repo> <dir> <body>
  mkdir -p "$1/$2"
  printf -- '---\nname: %s\n---\n%s\n' "${2##*/}" "$3" >"$1/$2/SKILL.md"
}

repo="$work/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config commit.gpgsign false
skill "$repo" plugins/core/skills/alpha "alpha v1"
skill "$repo" plugins/core/skills/beta "beta v1"
skill "$repo" plugins/extra/skills/delta "delta v1"
printf 'unchanged\n' >"$repo/README.md"
git -C "$repo" add -A
git -C "$repo" commit -q -m base

# The update: alpha modified, beta gains a reference file, gamma newly installed, delta removed.
skill "$repo" plugins/core/skills/alpha "alpha v2"
mkdir -p "$repo/plugins/core/skills/beta/references"
printf 'new reference\n' >"$repo/plugins/core/skills/beta/references/guide.md"
skill "$repo" plugins/extra/skills/gamma "gamma v1"
rm -rf "$repo/plugins/extra/skills/delta"
index_before="$(git -C "$repo" ls-files --stage | git hash-object --stdin)"

out="$work/out"
manifest="$(cd "$repo" && bash "$splitter" plugins "$out")" || fail "the splitter failed on an attributable update"

expected='[{"slug":"core-skills-alpha","path":"plugins/core/skills/alpha"},{"slug":"core-skills-beta","path":"plugins/core/skills/beta"},{"slug":"extra-skills-delta","path":"plugins/extra/skills/delta"},{"slug":"extra-skills-gamma","path":"plugins/extra/skills/gamma"}]'
[[ "$(jq -c . <<<"$manifest")" == "$expected" ]] ||
  fail "unexpected manifest: ${manifest}"
echo "ok: one entry per changed skill — modified, extended, removed and newly installed"

[[ "$(git -C "$repo" ls-files --stage | git hash-object --stdin)" == "$index_before" ]] ||
  fail "the splitter changed the caller's index"
echo "ok: the caller's index is left untouched"

# Each patch, applied alone to a fresh checkout of the base, reproduces exactly its skill's update.
while IFS=$'\t' read -r slug path; do
  fresh="$work/fresh-$slug"
  git clone -q "$repo" "$fresh"
  git -C "$fresh" apply --binary "$out/$slug.patch" || fail "$slug.patch does not apply to the base"
  touched="$(git -C "$fresh" status --porcelain --untracked-files=all | cut -c4-)"
  [[ -n "$touched" ]] || fail "$slug.patch changes nothing"
  while IFS= read -r file; do
    [[ "$file" == "$path/"* ]] || fail "$slug.patch touches $file, outside $path"
  done <<<"$touched"
  if [[ -d "$repo/$path" ]]; then
    diff -r "$repo/$path" "$fresh/$path" >/dev/null || fail "$slug.patch does not reproduce $path"
  else
    [[ ! -e "$fresh/$path" ]] || fail "$slug.patch does not remove $path"
  fi
done < <(jq -r '.[] | [.slug, .path] | @tsv' <<<"$manifest")
echo "ok: each patch applies alone and reproduces only its own skill"

# The workflow's default dir is the repository root; slugs then carry the full path.
root_manifest="$(cd "$repo" && bash "$splitter" . "$work/out-root")" || fail "the splitter failed with dir '.'"
[[ "$(jq -c '[.[].slug]' <<<"$root_manifest")" == '["plugins-core-skills-alpha","plugins-core-skills-beta","plugins-extra-skills-delta","plugins-extra-skills-gamma"]' ]] ||
  fail "unexpected manifest for dir '.': ${root_manifest}"
echo "ok: the repository root works as dir, with full-path slugs"

# A change that belongs to no skill must fail closed, never be dropped or bundled.
printf 'stray\n' >"$repo/plugins/core/stray.txt"
if err="$(cd "$repo" && bash "$splitter" plugins "$work/out-stray" 2>&1)"; then
  fail "the splitter accepted a change outside every skill"
fi
grep -qF "plugins/core/stray.txt" <<<"$err" || fail "the refusal does not name the stray file: ${err}"
rm "$repo/plugins/core/stray.txt"
echo "ok: a change outside every skill fails closed and is named"

# The single-PR mode commits every workspace change, so one outside dir must fail here too, not vanish.
printf 'outside\n' >"$repo/outside.txt"
if err="$(cd "$repo" && bash "$splitter" plugins "$work/out-outside" 2>&1)"; then
  fail "the splitter dropped a change outside dir"
fi
grep -qF "outside.txt" <<<"$err" || fail "the refusal does not name the change outside dir: ${err}"
rm "$repo/outside.txt"
echo "ok: a change outside dir fails closed and is named"

# No change at all is an empty manifest, not an error.
git -C "$repo" add -A
git -C "$repo" commit -q -m updated
manifest="$(cd "$repo" && bash "$splitter" plugins "$work/out-empty")" || fail "the splitter failed on a clean tree"
[[ "$(jq -c . <<<"$manifest")" == "[]" ]] || fail "a clean tree produced a manifest: ${manifest}"
echo "ok: a clean tree yields an empty manifest"

# A skill nested inside another is its own skill, and a skill name may hold a pathspec wildcard:
# neither may put one skill's files into another skill's patch.
skill "$repo" plugins/core/skills/alpha/sub "sub v1"
skill "$repo" 'plugins/core/skills/a*' "star v1"
git -C "$repo" add -A
git -C "$repo" commit -q -m nested
skill "$repo" plugins/core/skills/alpha "alpha v3"
skill "$repo" plugins/core/skills/alpha/sub "sub v2"
skill "$repo" 'plugins/core/skills/a*' "star v2"
manifest="$(cd "$repo" && bash "$splitter" plugins "$work/out-nested")" || fail "the splitter failed on nested skills"
[[ "$(jq -c 'sort_by(.path)' <<<"$manifest")" == '[{"slug":"core-skills-a-","path":"plugins/core/skills/a*"},{"slug":"core-skills-alpha","path":"plugins/core/skills/alpha"},{"slug":"core-skills-alpha-sub","path":"plugins/core/skills/alpha/sub"}]' ]] ||
  fail "unexpected manifest for nested skills: ${manifest}"
for pair in "core-skills-alpha=plugins/core/skills/alpha/SKILL.md" \
  "core-skills-alpha-sub=plugins/core/skills/alpha/sub/SKILL.md" \
  "core-skills-a-=plugins/core/skills/a*/SKILL.md"; do
  files="$(git -C "$repo" apply --numstat "$work/out-nested/${pair%%=*}.patch" | cut -f3)"
  [[ "$files" == "${pair#*=}" ]] || fail "${pair%%=*}.patch must touch only ${pair#*=}, got: ${files}"
done
git -C "$repo" add -A
git -C "$repo" commit -q -m nested-updated
echo "ok: a nested skill and a wildcard-named skill each get only their own files"

# The directory is a repository-relative path; anything else is refused.
for bad in /etc ../outside ""; do
  if (cd "$repo" && bash "$splitter" "$bad" "$work/out-bad") >/dev/null 2>&1; then
    fail "the splitter accepted dir '${bad}'"
  fi
done
echo "ok: absolute, escaping and empty directories are refused"

echo "PASS: per-skill splitting isolates every skill's update and fails closed on anything else"
