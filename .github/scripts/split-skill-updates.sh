#!/usr/bin/env bash

# Split one update-agent-skills run into one patch per changed skill (#1309), so a skill whose
# update is blocked strands only itself (devantler-tech/agent-plugins#175).
#
# usage: split-skill-updates.sh <dir> <out-dir>
#
# Run from the root of the caller's checkout after the update. Every change under <dir> is
# attributed to the nearest enclosing skill directory (one holding a SKILL.md before or after the
# update); <out-dir>/<slug>.patch holds that skill's binary diff against HEAD, without any skill
# nested inside it, and stdout is a compact JSON array of {"slug","path"} sorted by path. A change
# that belongs to no skill, including one outside <dir>, fails the run rather than being dropped or
# bundled into another skill's pull request. The caller's own index is never touched: staging
# happens in a temporary copy.

set -euo pipefail

fail() {
  echo "split-skill-updates: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || fail "usage: $0 <dir> <out-dir>"
dir="$1"
out_dir="$2"
[[ -n "$dir" && "$dir" != /* ]] || fail "dir must be a non-empty repository-relative path, got '$dir'"
case "/$dir/" in
  */../*) fail "dir must not leave the repository, got '$dir'" ;;
esac
[[ -d "$dir" ]] || fail "directory not found: $dir"
command -v jq >/dev/null || fail "jq is unavailable"

dir="${dir%/}"
[[ "$dir" == "." ]] && prefix="" || prefix="${dir#./}/"

work="$(mktemp -d)" || fail "could not create a work directory"
trap 'rm -rf "$work"' EXIT
export GIT_INDEX_FILE="$work/index"
real_index="$(git rev-parse --git-path index)" || fail "not inside a git checkout"
if [[ -f "$real_index" ]]; then
  cp "$real_index" "$GIT_INDEX_FILE" || fail "could not copy the index"
fi

# Stage the whole checkout, not only <dir>: the single-PR mode commits every workspace change, so a
# change outside <dir> must fail here rather than silently miss every per-skill pull request.
git add -A || fail "could not stage the update"
git diff --cached --name-only --no-renames -z >"$work/changed" ||
  fail "could not list the changes"

skill_of() {
  # skill_of <path>: the nearest enclosing directory holding a SKILL.md before or after the update.
  local d="${1%/*}"
  [[ "$d" == "$1" ]] && d="."
  while :; do
    if [[ -f "$d/SKILL.md" ]] || git cat-file -e "HEAD:${d#./}/SKILL.md" 2>/dev/null; then
      printf '%s\n' "${d#./}"
      return 0
    fi
    [[ "$d" == "." || "$d" == "${dir#./}" || "$d" == "$dir" ]] && return 1
    [[ "$d" == */* ]] && d="${d%/*}" || d="."
  done
}

: >"$work/skills"
: >"$work/stray"
while IFS= read -r -d '' path; do
  if [[ -n "$prefix" && "$path" != "$prefix"* ]]; then
    printf '%s\n' "$path" >>"$work/stray"
  elif skill="$(skill_of "$path")"; then
    printf '%s\n' "$skill" >>"$work/skills"
  else
    printf '%s\n' "$path" >>"$work/stray"
  fi
done <"$work/changed"

if [[ -s "$work/stray" ]]; then
  fail "these changes belong to no skill, so no per-skill pull request can carry them: $(paste -sd ' ' "$work/stray")"
fi

mkdir -p "$out_dir" || fail "could not create $out_dir"
sort -u "$work/skills" >"$work/skills.sorted"
manifest='[]'
while IFS= read -r skill; do
  [[ -n "$skill" ]] || continue
  rel="${skill#"$prefix"}"
  slug="$(printf '%s' "$rel" | tr '/' '-' | tr -c 'A-Za-z0-9._-' '-')"
  [[ -n "$slug" && "$slug" != "." ]] || fail "could not derive a branch-safe name for $skill"
  [[ ! -e "$out_dir/$slug.patch" ]] || fail "two skills map to the same name '$slug'"
  # Literal pathspecs, so a skill name holding `*`, `?` or `[` cannot match other skills, and a
  # changed skill nested inside this one is left to its own patch instead of riding along here.
  pathspec=(":(literal)$skill")
  while IFS= read -r other; do
    if [[ "$other" == "$skill/"* ]]; then pathspec+=(":(exclude,literal)$other"); fi
  done <"$work/skills.sorted"
  git diff --cached --binary --no-renames -- "${pathspec[@]}" >"$out_dir/$slug.patch" ||
    fail "could not write the patch for $skill"
  [[ -s "$out_dir/$slug.patch" ]] || fail "the patch for $skill is empty"
  manifest="$(jq -c --arg slug "$slug" --arg path "$skill" '. + [{slug:$slug,path:$path}]' <<<"$manifest")"
done <"$work/skills.sorted"

printf '%s\n' "$manifest"
