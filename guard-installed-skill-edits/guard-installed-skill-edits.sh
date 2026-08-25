#!/usr/bin/env bash
# Fail a PR that edits a file inside an already-installed skill tree whose
# SKILL.md at BASE_SHA carries metadata.github-repo provenance, unless the PR
# is the programmed sync (PR_ACTOR + PR_HEAD_BRANCH both match) or the skill
# directory is wholly new / wholly retired.
#
# Env:
#   BASE_SHA, HEAD_SHA — required when SKILL_ROOT exists
#   SKILL_ROOT — default .agents/skills
#   PR_ACTOR, PR_HEAD_BRANCH — programmed-sync exemption (both required)
#   SYNC_ACTOR — default botantler-1[bot]
#   SYNC_BRANCH — default deps/agent-skills-update
#   CHANGED_PATHS — optional newline-delimited test seam (production uses git diff -z)
set -euo pipefail

SKILL_ROOT="${SKILL_ROOT:-.agents/skills}"
SYNC_ACTOR="${SYNC_ACTOR:-botantler-1[bot]}"
SYNC_BRANCH="${SYNC_BRANCH:-deps/agent-skills-update}"

# Missing-dir no-op must precede the SHA check: this repo has no .agents/skills
# of its own, so an unset-root job on a random PR would otherwise fail UNKNOWN.
if [ ! -d "${SKILL_ROOT}" ]; then
  echo "guard-installed-skill-edits: no ${SKILL_ROOT}; nothing to check"
  exit 0
fi

if [ -z "${BASE_SHA:-}" ] || [ -z "${HEAD_SHA:-}" ]; then
  echo "UNKNOWN: BASE_SHA and HEAD_SHA are required" >&2
  exit 2
fi

if [ "${PR_ACTOR:-}" = "${SYNC_ACTOR}" ] && [ "${PR_HEAD_BRANCH:-}" = "${SYNC_BRANCH}" ]; then
  echo "guard-installed-skill-edits: programmed sync (${PR_ACTOR} on ${PR_HEAD_BRANCH}); exempt"
  exit 0
fi

provenance_repo() {
  local file="$1"
  awk '
    BEGIN { in_fm=0 }
    NR==1 && $0=="---" { in_fm=1; next }
    in_fm && $0=="---" { exit }
    in_fm {
      if (match($0, /^[[:space:]]*github-repo:[[:space:]]*(.*)$/, m)) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", m[1])
        gsub(/^["'\'']+|["'\'']+$/, "", m[1])
        print m[1]
        exit
      }
    }
  ' "$file"
}

skill_dir_of() {
  local path="$1"
  local prefix="${SKILL_ROOT%/}/"
  case "$path" in
    "${prefix}"*)
      local rest="${path#"$prefix"}"
      printf '%s\n' "${rest%%/*}"
      ;;
  esac
}

list_changed_paths() {
  if [ -n "${CHANGED_PATHS:-}" ]; then
    printf '%s\n' "${CHANGED_PATHS}"
    return 0
  fi
  git --no-replace-objects diff --name-only -z "${BASE_SHA}" "${HEAD_SHA}" -- "${SKILL_ROOT}" |
    tr '\0' '\n'
}

unknown=0
refused=0

while IFS= read -r path; do
  [ -n "$path" ] || continue
  skill_dir="$(skill_dir_of "$path")"
  [ -n "$skill_dir" ] || continue

  base_skill="${SKILL_ROOT%/}/${skill_dir}"
      if ! git --no-replace-objects cat-file -e "${BASE_SHA}:${base_skill}" 2>/dev/null; then
    continue
  fi

  skill_md="${base_skill}/SKILL.md"
    if ! git --no-replace-objects cat-file -e "${BASE_SHA}:${skill_md}" 2>/dev/null; then
    echo "UNKNOWN: ${base_skill} exists at base but SKILL.md is missing" >&2
    unknown=1
    continue
  fi

  tmp="$(mktemp)"
    git --no-replace-objects show "${BASE_SHA}:${skill_md}" >"$tmp"
  repo="$(provenance_repo "$tmp")"
  rm -f "$tmp"

  if [ -z "$repo" ]; then
    echo "UNKNOWN: ${skill_md} at base has empty metadata.github-repo" >&2
    unknown=1
    continue
  fi

  echo "refused: ${path} edits synced skill ${skill_dir} (upstream: ${repo}); fix it there, not here" >&2
  refused=1
done < <(list_changed_paths)

if [ "$unknown" -eq 1 ]; then
  exit 2
fi
if [ "$refused" -eq 1 ]; then
  exit 1
fi
exit 0
