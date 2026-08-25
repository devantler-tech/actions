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

# `.` (or an empty value after normalisation) means the skill directories live at the
# repository root. Git emits `synced/SKILL.md` with no prefix at all, so the prefix must be
# EMPTY — `./` matches nothing and the guard would pass having checked nothing.
if [ "${SKILL_ROOT}" = "." ] || [ -z "${SKILL_ROOT}" ]; then
  ROOT_DIR="."
  ROOT_PREFIX=""
else
  ROOT_DIR="${SKILL_ROOT}"
  ROOT_PREFIX="${SKILL_ROOT}/"
fi

# 🔴 A MISSING ROOT ONLY MEANS "NOTHING TO CHECK" IF THERE IS A CHECKOUT TO CHECK.
#
# Without one -- no `actions/checkout` step, a wrong `working-directory`, a job that cleaned
# the workspace -- EVERY path is absent, so the missing-root no-op below fires and this
# REQUIRED guard exits 0 having evaluated nothing at all. That is the same
# "valid input -> zero matches -> exit 0" fail-open the three-dot diff check further down
# already refuses for an unresolvable commit; a vanished worktree must not be the one route
# still permitted, because it is indistinguishable in the log from a genuinely clean tree.
#
# `--is-inside-work-tree` is the narrow question: a bare repository or no repository at all
# is UNKNOWN. The SHA checks stay where they are -- this only establishes that the answer
# below is about a real checkout.
#
# ⚠️ TEST THE VALUE, NEVER THE EXIT STATUS. Inside a BARE repository this command prints
# `false` and still exits 0, so `if ! git rev-parse ...` does not fire and the missing-root
# no-op below returns a clean exit 0 for a tree that has no working files at all.
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
  echo "UNKNOWN: not inside a git work tree — the guard cannot see what changed" >&2
  echo "UNKNOWN: check out the repository before running this action" >&2
  exit 2
fi

# 🔴 "IS THERE A SKILL ROOT?" IS A QUESTION ABOUT THE REFERENCED TREES, NOT THE CHECKOUT.
#
# Every decision below reads git objects — `cat-file -e "${BASE_SHA}:..."`, `show`, `diff` —
# and never touches a working file. Asking `-d` about the worktree therefore tested something
# the rest of this script does not use, and answered it wrongly whenever the two disagree: a
# sparse checkout that omits the root, or an earlier step that removed it, exits 0 here
# without examining the diff at all, while both commits contain the root and the PR edits a
# synced skill inside it. That is the same "valid input -> zero matches -> exit 0" fail-open
# the three-dot diff check refuses for an unresolvable commit.
#
# When both SHAs are present the trees are authoritative. Without them nothing can be
# diffed anyway, so the worktree question is kept as the fallback: a repository that simply
# has no skill root still no-ops instead of failing a required gate, and a root that DOES
# exist falls through to the UNKNOWN below.
root_in_tree() { # <sha> -> 0 when ROOT_DIR exists in that tree
  # Repository-root mode: every commit has a root tree, so there is nothing to look up.
  [ -z "${ROOT_PREFIX}" ] && return 0
  git --no-replace-objects cat-file -e "${1}:${ROOT_DIR}" 2>/dev/null
}

# 🔴 A MISSING COMMIT AND A COMMIT WITHOUT THE ROOT ARE THE SAME EXIT STATUS.
#
# `cat-file -e "${sha}:${ROOT_DIR}"` fails identically whether the commit is absent from
# this clone or present and simply has no such path. Under the depth-1 default of
# `actions/checkout` the base commit is routinely absent, so BOTH lookups fail, the "no
# root in either commit" branch fires, and this REQUIRED guard exits 0 before it ever
# reaches the diff or the UNKNOWN checks — passing without evaluating a single edit.
#
# That is the same "valid input -> zero matches -> exit 0" shape the diff check already
# refuses, and it is exactly what asking the TREES instead of the checkout was meant to
# close, so the object must be proven readable before its absence means anything.
commit_readable() { # <sha> -> 0 when the commit object is present in this clone
  git --no-replace-objects cat-file -e "${1}^{commit}" 2>/dev/null
}

if [ -n "${BASE_SHA:-}" ] && [ -n "${HEAD_SHA:-}" ]; then
  for _sha in "${BASE_SHA}" "${HEAD_SHA}"; do
    if ! commit_readable "${_sha}"; then
      echo "UNKNOWN: commit ${_sha} is not present in this clone — its absence cannot be read as an absent ${ROOT_DIR}" >&2
      echo "UNKNOWN: fetch both commits, or deepen the checkout (fetch-depth: 0)" >&2
      exit 2
    fi
  done
  if ! root_in_tree "${BASE_SHA}" && ! root_in_tree "${HEAD_SHA}"; then
    echo "guard-installed-skill-edits: no ${ROOT_DIR} in either commit; nothing to check"
    exit 0
  fi
elif [ ! -d "${ROOT_DIR}" ]; then
  echo "guard-installed-skill-edits: no ${ROOT_DIR}; nothing to check"
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

# Reads one YAML mapping entry's key, with the leading indentation already stripped by the
# caller. On success sets `_key` to the key name — quotes removed, whitespace before the colon
# trimmed — and `_rest` to everything after the colon, and returns 0. Returns 1 when the line
# is not a mapping entry this parser can read.
#
# 🔴 A RETURN OF 1 MEANS UNDECIDABLE, NEVER "NO SUCH KEY". Every caller must fail closed on it.
# Six different legal spellings of one SKILL.md have now reached the same fail-open — a
# column-zero comment, a comment's indentation, a flow mapping, a quoted child key in block
# style, a quoted key in flow style, and a quoted-or-spaced `metadata` parent — each time by
# not matching a pattern, reading as "no provenance recorded", and so being classified LOCAL,
# which PERMITS a hand-edit to a synced skill. Widening the pattern once more would only invite
# a seventh. So the question is no longer "which spellings do I recognise?" but "what is this
# key called?": extract it, normalise it, then compare against the one name that matters.
# Resolves `metadata.github-repo` from a SKILL.md's YAML front matter.
#
# Prints the upstream repository, an empty string when the skill records no provenance (the
# LOCAL verdict), or the `__UNKNOWN__` sentinel when the answer cannot be established. Empty
# and UNKNOWN are deliberately different values: empty PERMITS the edit, so letting "I could
# not read this" collapse into it is the exact fail-open this guard exists to refuse.
#
# 🔴 THIS USES A REAL YAML PARSER, AND THAT IS THE WHOLE POINT.
# The previous implementation decided the question with shell string operations, and over nine
# review rounds that produced nineteen defects in this one function — in BOTH directions. Keys
# went unread and the skill was silently classified local (a column-zero comment, a comment's
# indentation, flow style, quoted keys in block and flow form, a quoted or space-padded
# `metadata`, `github-repo :`, `-` escapes, merge aliases, multi-line scalars, an indented
# root); and ordinary local metadata was refused outright (`github-repo: null`, a comment-only
# value, a comma inside `[a, b]` or `"a,b"`, a brace inside a quoted scalar, a comment after a
# quoted empty value). Every one was a correct fix and every round produced more, because
# quoting, escapes, anchors, merge keys, flow style, null forms and comment rules are things a
# YAML parser already knows and a line-oriented matcher has to re-learn one incident at a time.
#
# yq resolves anchors, aliases and merge keys natively, so several inputs that could only fail
# closed before now produce a real verdict. `--front-matter=extract` reads the leading `---`
# block of a Markdown file, which is exactly the shape of a SKILL.md.
provenance_repo() {
  local file="$1" out rc tag
  # A parser this depends on must be present, and its absence is UNDECIDABLE — never local.
  if ! command -v yq >/dev/null 2>&1; then
    printf '%s\n' "__UNKNOWN__"
    return 0
  fi
  # `// ""` maps both an absent key and an explicit YAML null to the LOCAL verdict, which is
  # what those spellings mean. A parse failure exits non-zero and is undecidable.
  out="$(yq --front-matter=extract -r '.metadata.github-repo // ""' "$file" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "__UNKNOWN__"
    return 0
  fi
  # 🔴 CLASSIFY BY YAML TAG, NOT BY WHAT THE VALUE LOOKS LIKE ONCE RENDERED.
  # A mapping or sequence names no upstream, and handing one to a later string comparison is a
  # verdict about a value that is not a repository name. The obvious test — does the rendered
  # text start with `{` or `[`, or contain a newline — is a heuristic over yq's OUTPUT STYLE,
  # which is configurable and version-dependent. That is the same shape-matching this rewrite
  # exists to remove, one level up. The tag is the structural fact: `!!str` and `!!null` are
  # answerable, everything else is undecidable.
  # The SAME expression as the value read above, so the tag and the value cannot disagree. A bare
  # `.metadata.github-repo | tag` returns an EMPTY tag with rc=0 where `.metadata` is a scalar —
  # a silent third state that the rc check does not catch and that would read as non-scalar.
  tag="$(yq --front-matter=extract -r '.metadata.github-repo // "" | tag' "$file" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "__UNKNOWN__"
    return 0
  fi
  case "$tag" in
    '!!str'|'!!null') : ;;
    *) printf '%s\n' "__UNKNOWN__"; return 0 ;;
  esac
  # No `null` case here: `// ""` above already maps YAML null to the empty string. Adding one
  # would only reclassify the QUOTED scalar `"null"`, which is a deliberate string value and
  # not an absent one.
  printf '%s\n' "$out"
}

skill_dir_of() {
  local path="$1"
  local prefix="${ROOT_PREFIX}"
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
    # The seam is newline-delimited (action.yaml pins CHANGED_PATHS to empty, so this arm
    # is reachable only from the hermetic suite). Re-emit it NUL-delimited so both arms speak
    # one delimiter and the consumer never has to know which one ran.
    printf '%s' "${CHANGED_PATHS}" | tr '\n' '\0'
    return 0
  fi
  # THREE-dot: the paths this PR changed relative to the merge base, never the two-commit
  # difference. With a two-dot diff a base branch that advanced after the PR branched drags
  # the base-only changes in. Provenance is still read from the BASE_SHA snapshot below.
  # 🔴 CONSUME THE -z OUTPUT AS-IS. Translating NUL to newline splits a Git-valid path that
  # CONTAINS a newline into two records: the first has no directory component below the root
  # and the second has lost the root prefix, so BOTH are ignored and an edit to a provenanced
  # skill exits 0. NUL is the one delimiter that cannot occur inside a path.
  git --no-replace-objects diff --name-only -z "${BASE_SHA}...${HEAD_SHA}" -- "${ROOT_DIR}"
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

while IFS= read -r -d '' path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  skill_dir="$(skill_dir_of "$path")"
  [ -n "$skill_dir" ] || continue

  base_skill="${ROOT_PREFIX}${skill_dir}"
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
    # 🔴 IN REPOSITORY-ROOT MODE, A TOP-LEVEL DIRECTORY IS NOT A SKILL BY CONSTRUCTION.
    #
    # Under a dedicated root every subdirectory is MEANT to be a skill, so one without a
    # SKILL.md is a genuinely broken install and UNKNOWN is right. With the documented
    # `skill-root: .` the first path component of every changed file is a candidate, so
    # editing `.github/workflows/ci.yaml` selects `.github` — a directory that exists in
    # both trees and has no SKILL.md — and this branch failed an unrelated PR with exit 2.
    # That fires on essentially every PR in a root-mode consumer, which is a false refusal
    # severe enough to teach people to remove the gate.
    #
    # This cannot hide an edit: provenance is read from the BASE snapshot, so a directory
    # with no SKILL.md at base is not an installed skill at base and has nothing to protect.
    if [ -z "${ROOT_PREFIX}" ]; then
      continue
    fi
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

  # An undecidable metadata mapping is UNKNOWN, never local. `provenance_repo` returns a
  # sentinel rather than an empty string precisely because empty is the LOCAL verdict here,
  # and letting "I could not parse this" collapse into it is the fail-open this guard exists
  # to refuse.
  if [ "$repo" = "__UNKNOWN__" ]; then
    echo "UNKNOWN: ${skill_md} at base carries a metadata mapping this guard cannot parse" >&2
    unknown=1
    continue
  fi

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
