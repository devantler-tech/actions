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
  local file="$1" line value first=1 in_fm=0 in_meta=0 meta_indent="" indent
  # Only a DIRECT child `metadata.github-repo` counts. A top-level key, or one nested
  # deeper (e.g. `metadata.source.github-repo`), must NOT mark a skill as synced, or a
  # stray key could make a local skill un-editable. Pure-bash because awk's
  # three-argument match() is a GNU extension and the default awk is mawk on Ubuntu
  # runners and BSD awk on macOS.
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" = 1 ]; then
      first=0
      if [ "$line" = "---" ]; then in_fm=1; continue; fi
      return 0
    fi
    [ "$in_fm" = 1 ] || continue
    [ "$line" = "---" ] && return 0
    # A non-indented line starts a new top-level key, which closes any metadata mapping.
    case "$line" in
      [!\ \	]*)
        if [[ $line =~ ^metadata:[[:space:]]*(#.*)?$ ]]; then in_meta=1; else in_meta=0; fi
        meta_indent=""
        continue
        ;;
    esac
    [ "$in_meta" = 1 ] || continue
    # Blank lines carry no indentation and never establish the child level.
    [[ $line =~ ^[[:space:]]*$ ]] && continue
    # Indentation of this line, as a literal prefix string (tabs and spaces both count
    # as one level-character each; YAML forbids tabs for indentation, so a mixed file is
    # malformed anyway and falls through to UNKNOWN rather than being trusted).
    indent="${line%%[![:space:]]*}"
    # The first non-blank indented line after `metadata:` fixes the direct-child level.
    if [ -z "$meta_indent" ]; then meta_indent="$indent"; fi
    # Anything deeper (or shallower) than that level is not a direct child.
    [ "$indent" = "$meta_indent" ] || continue
    if [[ $line =~ ^[[:space:]]+github-repo:[[:space:]]*(.*)$ ]]; then
      value="${BASH_REMATCH[1]}"
      value="${value%"${value##*[![:space:]]}"}"
      value="${value#\"}"; value="${value%\"}"
      value="${value#\'}"; value="${value%\'}"
      printf '%s\n' "$value"
      return 0
    fi
  done <"$file"
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
  # THREE-dot: the paths this PR changed relative to the merge base, never the
  # two-commit difference. With a two-dot diff, a base branch that advanced after the
  # PR branched drags the base-only changes in — so the programmed updater editing a
  # synced skill on the base would make the guard refuse an unrelated PR that never
  # touched it. Provenance is still read from the BASE_SHA snapshot below.
  git --no-replace-objects diff --name-only -z "${BASE_SHA}...${HEAD_SHA}" -- "${SKILL_ROOT}" |
    tr '\0' '\n'
}

unknown=0
refused=0

# Capture the path list in a command whose exit status is CHECKED. Reading it straight
# from a process substitution discards the status, so an unresolvable SHA or a shallow
# `actions/checkout` (depth 1, where the base commit is absent) makes `git diff` fail,
# feeds the loop nothing, and the guard exits 0 having permitted every edit — a silent
# fail-open in exactly the configuration most consumers run.
changed_paths="$(mktemp)"
trap 'rm -f "${changed_paths}"' EXIT
if ! list_changed_paths >"${changed_paths}"; then
  echo "UNKNOWN: could not determine changed paths between ${BASE_SHA} and ${HEAD_SHA}" >&2
  echo "UNKNOWN: both commits must be present locally — fetch them, or deepen the checkout" >&2
  exit 2
fi

while IFS= read -r path; do
  [ -n "$path" ] || continue
  skill_dir="$(skill_dir_of "$path")"
  [ -n "$skill_dir" ] || continue

  base_skill="${SKILL_ROOT%/}/${skill_dir}"
  if ! git --no-replace-objects cat-file -e "${BASE_SHA}:${base_skill}" 2>/dev/null; then
    continue
  fi

  # Wholesale retirement: the skill existed at base and is gone at head. Removing an
  # installed skill is a legitimate local decision — only EDITING a synced one is not.
  if ! git --no-replace-objects cat-file -e "${HEAD_SHA}:${base_skill}" 2>/dev/null; then
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
done <"${changed_paths}"

if [ "$unknown" -eq 1 ]; then
  exit 2
fi
if [ "$refused" -eq 1 ]; then
  exit 1
fi
exit 0
