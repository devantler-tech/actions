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
# Normalise before ANY use. Git emits repository-relative paths with no `./` prefix and no
# trailing slash, so a consumer passing `./.agents/skills` (valid, and what a copied YAML
# snippet often carries) would make every prefix comparison below fail and the guard would
# exit 0 having matched nothing — silently permitting the edits it exists to refuse.
while [ "${SKILL_ROOT#./}" != "${SKILL_ROOT}" ]; do SKILL_ROOT="${SKILL_ROOT#./}"; done
while [ "${SKILL_ROOT%/}" != "${SKILL_ROOT}" ]; do SKILL_ROOT="${SKILL_ROOT%/}"; done
SYNC_ACTOR="${SYNC_ACTOR:-botantler-1[bot]}"
SYNC_BRANCH="${SYNC_BRANCH:-deps/agent-skills-update}"

if [ -z "${SKILL_ROOT}" ]; then
  echo "UNKNOWN: SKILL_ROOT normalised to an empty path" >&2
  exit 2
fi

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
  # deeper (e.g. `metadata.source.github-repo`), is not provenance. Pure-bash because awk's
  # three-argument match() is a GNU extension and the default awk is mawk on Ubuntu runners
  # and BSD awk on macOS.
  while IFS= read -r line || [ -n "$line" ]; do
    # A CRLF-committed SKILL.md is valid; without stripping the CR the very first line does
    # not equal `---`, front matter is never entered, and a synced skill reads as having no
    # provenance at all.
    line="${line%$'\r'}"
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
  local prefix="${SKILL_ROOT}/"
  case "$path" in
    "${prefix}"*)
      local rest="${path#"$prefix"}"
      # Only a path with a directory component below the root names a skill. A housekeeping
      # file sitting directly under the root (`README.md`, `.gitkeep`) has no slash, and
      # returning its filename as a skill name made the guard look for `<file>/SKILL.md`,
      # find nothing, and block an unrelated edit as UNKNOWN.
      case "$rest" in
        */*) printf '%s\n' "${rest%%/*}" ;;
      esac
      ;;
  esac
}

list_changed_paths() {
  if [ -n "${CHANGED_PATHS:-}" ]; then
    printf '%s\n' "${CHANGED_PATHS}"
    return 0
  fi
  # THREE-dot: the paths this PR changed relative to the merge base, never the two-commit
  # difference. With a two-dot diff a base branch that advanced after the PR branched drags
  # the base-only changes in. Provenance is still read from the BASE_SHA snapshot below.
  git --no-replace-objects diff --name-only -z "${BASE_SHA}...${HEAD_SHA}" -- "${SKILL_ROOT}" |
    tr '\0' '\n'
}

unknown=0
refused=0

# Capture the path list in a command whose exit status is CHECKED. Reading it straight from
# a process substitution discards the status, so an unresolvable SHA or a shallow checkout
# makes `git diff` fail, feeds the loop nothing, and the guard exits 0 having permitted
# every edit.
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

  base_skill="${SKILL_ROOT}/${skill_dir}"
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
  # A failed read is UNKNOWN. This check is what lets "no provenance" mean "local" below:
  # without it an unreadable SKILL.md would produce an empty result and be waved through.
  if ! git --no-replace-objects show "${BASE_SHA}:${skill_md}" >"$tmp" 2>/dev/null; then
    echo "UNKNOWN: cannot read ${skill_md} at base" >&2
    unknown=1
    rm -f "$tmp"
    continue
  fi
  repo="$(provenance_repo "$tmp")"
  rm -f "$tmp"

  if [ -z "$repo" ]; then
    # SKILL.md was read successfully and records no direct metadata.github-repo, so this
    # skill is LOCAL and editing it is a local decision. UNKNOWN is reserved for records
    # that could not be read at all — blocking here made every local skill uneditable,
    # which is the false positive that teaches people to route around the guard.
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
