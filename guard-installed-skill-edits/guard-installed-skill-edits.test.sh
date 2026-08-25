#!/usr/bin/env bash
# Hermetic tests for guard-installed-skill-edits.sh.
# Stubs git so the suite never needs a real repository or network.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
guard="${root}/guard-installed-skill-edits/guard-installed-skill-edits.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
PATH="${tmp}/bin:${PATH}"
export PATH

mkdir -p "${tmp}/bin" "${tmp}/objects"
cat >"${tmp}/bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
store="${FAKE_GIT_STORE:?}"
    while [ $# -gt 0 ]; do
      case "${1}" in
        --no-replace-objects) shift ;;
        -C) shift 2 ;;
        *) break ;;
      esac
    done
    cmd="${1:-}"
shift || true
case "${cmd}" in
  show)
    spec="${1:-}"
    key="${spec//\//_}"
    key="${key//:/_}"
    f="${store}/show/${key}"
    [ -f "${f}" ] || exit 128
    # Sentinel: the blob EXISTS (so `cat-file -e` succeeds) but cannot be read. This is
    # what separates "unreadable record" (UNKNOWN) from "no provenance recorded" (local).
    [ "$(cat "${f}")" = "__UNREADABLE__" ] && exit 128
    cat "${f}"
    ;;
  cat-file)
    [ "${1:-}" = "-e" ] || exit 1
    spec="${2:-}"
    # Commit-object readability. Default READABLE, because every other fixture models a
    # real checkout that has both commits; the `unreadable_commits` sentinel models the
    # depth-1 shallow checkout where the base commit is simply absent. A stub with no
    # handler here would answer "unreadable" for every fixture and send them all down the
    # UNKNOWN branch — untested, not passing.
    case "${spec}" in
      *'^{commit}')
        base="${spec%'^{commit}'}"
        if [ -f "${store}/unreadable_commits" ] && grep -qxF -- "${base}" "${store}/unreadable_commits"; then
          exit 1
        fi
        exit 0
        ;;
    esac
    key="${spec//\//_}"
    key="${key//:/_}"
    # A DIRECTORY resolves when anything is stored UNDER it, which is what real git answers
    # for `cat-file -e <sha>:<dir>`. Requiring an explicit entry per directory made the stub
    # answer "absent" for a tree that demonstrably contains files — so a guard asking about
    # the skill ROOT was tested against a fiction. Glob rather than a regex: the key holds
    # dots and dashes that a `grep "^${key}_"` anchor would treat as metacharacters.
    if [ -f "${store}/show/${key}" ]; then exit 0; fi
    for entry in "${store}/show/${key}"_*; do
      if [ -e "${entry}" ]; then exit 0; fi
    done
    exit 1
    ;;
  ls-tree)
    [ "${1:-}" = "-r" ] && [ "${2:-}" = "--name-only" ] || exit 1
    ref="${3:-}"
    prefix="${5:-}"
    key="${ref//\//_}"
    f="${store}/lstree/${key}"
    [ -f "${f}" ] || exit 0
    if [ -n "${prefix}" ]; then
      grep -F -- "${prefix}" "${f}" || true
    else
      cat "${f}"
    fi
    ;;
  rev-parse)
    # The guard asks exactly one rev-parse question: `--is-inside-work-tree`.
    #
    # A stub with NO handler for a production command does not make that path pass -- it
    # makes it UNTESTED, and here it silently sent every fixture down the UNKNOWN branch.
    # Default TRUE, because every other fixture models a real checkout.
    #
    # The `not_worktree` sentinel flips it to the no-checkout / bare-repository case. Note
    # it prints `false` and still exits 0: that is what real git does in a bare repository,
    # and reproducing the VALUE rather than an error status is the whole point -- a stub
    # that exited non-zero here would let a guard testing only the exit status pass.
    [ "${1:-}" = "--is-inside-work-tree" ] || exit 99
    if [ -f "${store}/not_worktree" ]; then echo false; else echo true; fi
    ;;
  diff)
    # Records the revision spec so a test can assert the THREE-dot form, and fails
    # when the fixture asks it to — the production fail-open lived exactly here.
    printf '%s\n' "$*" >"${store}/diff_args"
    [ -f "${store}/diff_fail" ] && exit 128
    [ -f "${store}/diff_out" ] && cat "${store}/diff_out"
    ;;
  *)
    echo "unexpected git $*" >&2
    exit 99
    ;;
esac
EOF
chmod +x "${tmp}/bin/git"

store_exists() {
  local spec="$1" body="$2"
  local key="${spec//\//_}"
  key="${key//:/_}"
  mkdir -p "$(dirname "${FAKE_GIT_STORE}/show/${key}")"
  printf '%s' "${body}" >"${FAKE_GIT_STORE}/show/${key}"
}

# Models an existing installed skill: the directory present at BOTH base and head (so the guard
# sees an EDIT rather than a creation or a retirement), plus its base-side front matter — which
# is where provenance is read from. Each case below then shows only the SKILL.md spelling it is
# actually testing.
new_case() {
  # NOTE: two `local` statements, not one. bash 3.2 — the macOS default — does not make an
  # earlier assignment in the SAME `local` visible to a later one, so a combined declaration dies
  # with `skill: unbound variable` under `set -u`. CI runs bash 5, where it works, so this is a
  # portability break CI cannot see.
  local store="$1" skill="$2" front_matter="$3"
  local path=".agents/skills/${skill}"
  export FAKE_GIT_STORE="${tmp}/${store}"
  mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree" "${tmp}/${path}"
  store_exists "origin/main:${path}" "dir"
  store_exists "HEAD:${path}" "dir"
  store_exists "origin/main:${path}/SKILL.md" "${front_matter}"
}

# Uses ${VAR-default} (not ${VAR:-default}) so an explicit empty SHA is not replaced.
run_guard() {
  (
    cd "$tmp"
    env -i \
      PATH="${PATH}" \
      HOME="${tmp}" \
      FAKE_GIT_STORE="${FAKE_GIT_STORE}" \
      SKILL_ROOT="${SKILL_ROOT-.agents/skills}" \
      BASE_SHA="${BASE_SHA-origin/main}" \
      HEAD_SHA="${HEAD_SHA-HEAD}" \
      PR_ACTOR="${PR_ACTOR-}" \
      PR_HEAD_BRANCH="${PR_HEAD_BRANCH-}" \
      SYNC_ACTOR="${SYNC_ACTOR-botantler-1[bot]}" \
      SYNC_BRANCH="${SYNC_BRANCH-deps/agent-skills-update}" \
      CHANGED_PATHS="${CHANGED_PATHS-}" \
      bash "${guard}"
  )
}

# 1. Missing SHA is UNKNOWN — skill root must exist so the SHA check is reached
#    (a missing root is an earlier no-op, even with empty GitHub context).
export FAKE_GIT_STORE="${tmp}/objects"
mkdir -p "${tmp}/.agents/skills"
if BASE_SHA="" HEAD_SHA="" run_guard; then
  fail "missing SHA: expected unknown"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "missing SHA: rc=${rc} want=2"
fi
pass "missing SHA is UNKNOWN"

# 2. Missing skill root is a no-op
rm -rf "${tmp}/.agents"
if SKILL_ROOT=".agents/skills" BASE_SHA="" HEAD_SHA="" run_guard; then :; else
  fail "missing skill root should no-op"
fi
pass "missing skill root is a no-op"

# 3. New skill directory is allowed
mkdir -p "${tmp}/.agents/skills/brand-new"
printf '%s\n' ".agents/skills/brand-new/SKILL.md" >"${tmp}/lstree-head"
export FAKE_GIT_STORE="${tmp}/objects2"
mkdir -p "${FAKE_GIT_STORE}/lstree" "${FAKE_GIT_STORE}/show"
# The root exists at HEAD because the new skill is in it; it is absent at base. Without
# this the root-existence check short-circuits and the case never reaches the loop it is
# meant to exercise.
store_exists "HEAD:.agents/skills/brand-new" "dir"
store_exists "HEAD:.agents/skills/brand-new/SKILL.md" $'---\nname: brand-new\n---\n'
printf '%s\n' ".agents/skills/brand-new/SKILL.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if CHANGED_PATHS=".agents/skills/brand-new/SKILL.md"$'\n' run_guard; then :; else
  fail "new skill directory should be allowed"
fi
pass "new skill directory is allowed"

# 4. Synced skill edit is refused
export FAKE_GIT_STORE="${tmp}/objects3"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/ways-of-working"
store_exists "origin/main:.agents/skills/ways-of-working" "dir"
store_exists "HEAD:.agents/skills/ways-of-working" "dir"   # still present at head: an edit, not a retirement
store_exists "origin/main:.agents/skills/ways-of-working/SKILL.md" $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
printf '%s\n' ".agents/skills/ways-of-working/SKILL.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if out="$(CHANGED_PATHS=".agents/skills/ways-of-working/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "synced skill edit should be refused"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "synced skill edit: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "fix it there, not here" || fail "missing failure message"
  printf '%s' "${out}" | grep -q "devantler-tech/agent-skills" || fail "missing upstream"
fi
pass "synced skill edit is refused with upstream"

# 5. Provenance is read at BASE, not HEAD
export FAKE_GIT_STORE="${tmp}/objects4"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/spoof"
store_exists "origin/main:.agents/skills/spoof" "dir"
store_exists "HEAD:.agents/skills/spoof" "dir"   # still present at head: an edit, not a retirement
store_exists "origin/main:.agents/skills/spoof/SKILL.md" $'---\nmetadata:\n  github-repo: https://github.com/evil/spoof\n---\n'
store_exists "HEAD:.agents/skills/spoof/SKILL.md" $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
printf '%s\n' ".agents/skills/spoof/SKILL.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if out="$(CHANGED_PATHS=".agents/skills/spoof/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "HEAD-spoofed provenance should still refuse"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "HEAD-spoof: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "evil/spoof" || fail "should name BASE upstream"
fi
pass "provenance is read at BASE"

# 6. Empty provenance at BASE is UNKNOWN
export FAKE_GIT_STORE="${tmp}/objects5"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/empty"
store_exists "origin/main:.agents/skills/empty" "dir"
store_exists "HEAD:.agents/skills/empty" "dir"   # still present at head: an edit, not a retirement
store_exists "origin/main:.agents/skills/empty/SKILL.md" $'---\nname: empty\n---\n'
printf '%s\n' ".agents/skills/empty/SKILL.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if CHANGED_PATHS=".agents/skills/empty/SKILL.md"$'\n' run_guard; then :; else
  rc=$?
  fail "a skill with no provenance is local and editable: rc=${rc} want=0 — no provenance means LOCAL, and a local skill is editable"
fi
pass "a skill with no provenance is local and editable"

# 7. Programmed-sync exemption needs actor AND branch
export FAKE_GIT_STORE="${tmp}/objects6"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/ways-of-working"
store_exists "origin/main:.agents/skills/ways-of-working" "dir"
store_exists "HEAD:.agents/skills/ways-of-working" "dir"   # still present at head: an edit, not a retirement
store_exists "origin/main:.agents/skills/ways-of-working/SKILL.md" $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
printf '%s\n' ".agents/skills/ways-of-working/SKILL.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if ! PR_ACTOR="botantler-1[bot]" PR_HEAD_BRANCH="deps/agent-skills-update" \
  CHANGED_PATHS=".agents/skills/ways-of-working/SKILL.md"$'\n' run_guard; then
  fail "programmed-sync exemption should pass"
fi
if PR_ACTOR="botantler-1[bot]" PR_HEAD_BRANCH="not-the-sync-branch" \
  CHANGED_PATHS=".agents/skills/ways-of-working/SKILL.md"$'\n' run_guard; then
  fail "actor-only should still refuse"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "actor-only: rc=${rc} want=1"
fi
pass "programmed-sync exemption needs actor AND branch"

# 8. Retiring a skill WHOLESALE is allowed — it must exist at BASE (with provenance) and
#    be ABSENT at HEAD. Storing nothing at BASE would exercise the new-skill path instead
#    and pass without ever reaching the retirement branch.
export FAKE_GIT_STORE="${tmp}/objects7"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
store_exists "origin/main:.agents/skills/retired" "dir"
store_exists "origin/main:.agents/skills/retired/SKILL.md" $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
# deliberately NOT stored at HEAD -> the skill is gone at head
: >"${FAKE_GIT_STORE}/lstree/HEAD"
if CHANGED_PATHS=".agents/skills/retired/SKILL.md"$'\n' run_guard; then :; else
  fail "retiring a skill should be allowed"
fi
pass "retiring a synced skill wholesale is allowed"

# 8b. Control for 8: the SAME synced skill still PRESENT at HEAD is refused, so case 8
#     passes because of the retirement branch and not because provenance went unread.
store_exists "HEAD:.agents/skills/retired" "dir"
if CHANGED_PATHS=".agents/skills/retired/SKILL.md"$'\n' run_guard; then
  fail "control: still-present synced skill should be refused"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "control: still-present synced skill rc=${rc} want=1"
fi
pass "control: the same skill still present at HEAD is refused"

# 8c. Provenance is only `metadata.github-repo`. A TOP-LEVEL github-repo key must not
#     mark a local skill as synced, or a stray key could make it un-editable.
export FAKE_GIT_STORE="${tmp}/objects7c"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
store_exists "origin/main:.agents/skills/toplevel" "dir"
store_exists "origin/main:.agents/skills/toplevel/SKILL.md" $'---\nname: toplevel\ngithub-repo: https://github.com/someone/else\n---\n'
store_exists "HEAD:.agents/skills/toplevel" "dir"
if CHANGED_PATHS=".agents/skills/toplevel/SKILL.md"$'\n' run_guard; then :; else
  rc=$?
  fail "a top-level github-repo is not metadata provenance: rc=${rc} want=0 — no provenance means LOCAL, and a local skill is editable"
fi
pass "a top-level github-repo is not metadata provenance"

# 9. SKILL.md gone at BASE while the directory remains is UNKNOWN
export FAKE_GIT_STORE="${tmp}/objects8"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/orphan"
store_exists "origin/main:.agents/skills/orphan" "dir"
store_exists "HEAD:.agents/skills/orphan" "dir"   # still present at head: an edit, not a retirement
printf '%s\n' ".agents/skills/orphan/README.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if CHANGED_PATHS=".agents/skills/orphan/README.md"$'\n' run_guard; then
  fail "orphan dir: expected unknown"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "orphan dir: rc=${rc} want=2"
fi
pass "SKILL.md gone at BASE while directory remains is UNKNOWN"

# 10. A FAILING changed-path diff is UNKNOWN, never a silent pass. Reading the path list
#     from a process substitution discarded git's exit status, so a shallow checkout (the
#     depth-1 default of actions/checkout, where the base commit is absent) fed the loop
#     nothing and the guard exited 0 having permitted every edit.
export FAKE_GIT_STORE="${tmp}/objects9"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
# The root must exist in a referenced TREE, not merely in the checkout, or the guard
# correctly no-ops before it ever runs the diff this case is about.
store_exists "origin/main:.agents/skills/installed/SKILL.md" $'---\nname: installed\n---\n'
: >"${FAKE_GIT_STORE}/diff_fail"
if run_guard; then
  fail "failing diff: expected UNKNOWN, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "failing diff: rc=${rc} want=2"
fi
pass "a failing changed-path diff is UNKNOWN, not a silent pass"

# 11. The changed-path diff uses the THREE-dot (merge-base) form. With a two-dot diff a
#     base branch that advanced after the PR branched drags its base-only changes in, so
#     the updater editing a synced skill on the base would refuse an unrelated PR.
export FAKE_GIT_STORE="${tmp}/objects10"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
# An unrelated installed skill, so the ROOT exists in a referenced tree and the guard
# reaches the diff. The changed path below still names a directory that is absent.
store_exists "origin/main:.agents/skills/present/SKILL.md" $'---\nname: present\n---\n'
printf '%s\0' ".agents/skills/absent/SKILL.md" >"${FAKE_GIT_STORE}/diff_out"
run_guard >/dev/null 2>&1 || true
[ -f "${FAKE_GIT_STORE}/diff_args" ] || fail "three-dot: the guard never invoked git diff"
grep -qF -- 'origin/main...HEAD' "${FAKE_GIT_STORE}/diff_args" \
  || fail "three-dot: expected 'origin/main...HEAD', got: $(cat "${FAKE_GIT_STORE}/diff_args")"
grep -qE -- '(^| )origin/main\.\.HEAD( |$)' "${FAKE_GIT_STORE}/diff_args" \
  && fail "three-dot: a two-dot spec was used"
pass "changed paths come from the three-dot merge-base diff"

# 12. Provenance must be a DIRECT child of metadata. A deeper key such as
#     metadata.source.github-repo is not provenance, so a local skill carrying one stays
#     editable instead of being refused against someone else's repository.
new_case objects11 nested \
  $'---\nmetadata:\n  source:\n    github-repo: https://github.com/someone/else\n---\n'
if CHANGED_PATHS=".agents/skills/nested/SKILL.md"$'\n' run_guard; then :; else
  rc=$?
  fail "metadata.source.github-repo is not provenance: rc=${rc} want=0 — no provenance means LOCAL, and a local skill is editable"
fi
pass "metadata.source.github-repo is not provenance"

# 12b. Control for 12: a genuine DIRECT metadata.github-repo, in a file whose front matter
#      is otherwise shaped identically, is still detected and still refused. Without this,
#      case 12 would also pass if the parser had simply stopped reading provenance at all.
new_case objects11b nested \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n  source:\n    github-repo: https://github.com/someone/else\n---\n'
if CHANGED_PATHS=".agents/skills/nested/SKILL.md"$'\n' run_guard; then
  fail "control: a direct metadata.github-repo should still refuse"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "control: rc=${rc} want=1"
fi
pass "control: a direct metadata.github-repo is still detected"

# 13. `metadata:` may carry a trailing YAML comment. Requiring the line to end right after
#     the colon made the parser skip the mapping and report UNKNOWN for a skill that has
#     perfectly valid provenance — fail-closed, but still wrong.
new_case objects12 commented \
  $'---\nmetadata: # upstream ownership\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/commented/SKILL.md"$'\n' run_guard; then
  fail "commented metadata key: expected a refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "commented metadata key: rc=${rc} want=1 (provenance must still be read)"
fi
pass "a trailing comment after metadata: does not hide provenance"

# 13b. Control for 13: the match is still anchored to the exact key, so a different
#      top-level key that merely starts with the same letters does not open the mapping.
new_case objects12b decoy \
  $'---\nmetadataX: # decoy\n  github-repo: https://github.com/someone/else\n---\n'
if CHANGED_PATHS=".agents/skills/decoy/SKILL.md"$'\n' run_guard; then :; else
  rc=$?
  fail "control: metadataX: does not open the metadata mapping: rc=${rc} want=0 — no provenance means LOCAL, and a local skill is editable"
fi
pass "control: metadataX: does not open the metadata mapping"

# 14. An UNREADABLE provenance record is still UNKNOWN. This is the companion to case 6:
#     "no provenance" may mean local only because a failed read is caught separately — without
#     this, an unreadable SKILL.md would yield an empty result and be waved through.
export FAKE_GIT_STORE="${tmp}/objects13"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/unreadable"
store_exists "origin/main:.agents/skills/unreadable" "dir"
store_exists "HEAD:.agents/skills/unreadable" "dir"
store_exists "origin/main:.agents/skills/unreadable/SKILL.md" "__UNREADABLE__"
if CHANGED_PATHS=".agents/skills/unreadable/SKILL.md"$'\n' run_guard; then
  fail "unreadable SKILL.md: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "unreadable SKILL.md: rc=${rc} want=2"
fi
pass "an unreadable provenance record is UNKNOWN, not 'local'"

# 15. A `./`-prefixed skill root still matches. Git emits repository-relative paths with no
#     `./`, so an un-normalised prefix matched nothing and the guard exited 0 having checked
#     nothing at all — a silent fail-open reachable from a perfectly valid input value.
new_case objects14 ways-of-working \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if SKILL_ROOT="./.agents/skills" CHANGED_PATHS=".agents/skills/ways-of-working/SKILL.md"$'\n' run_guard; then
  fail "./-prefixed root: expected a refusal, got success (fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "./-prefixed root: rc=${rc} want=1"
fi
pass "a ./-prefixed skill root is normalised and still refuses"

# 15b. Same for a trailing slash, which is equally valid to supply.
if SKILL_ROOT=".agents/skills/" CHANGED_PATHS=".agents/skills/ways-of-working/SKILL.md"$'\n' run_guard; then
  fail "trailing-slash root: expected a refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "trailing-slash root: rc=${rc} want=1"
fi
pass "a trailing-slash skill root is normalised and still refuses"

# 16. A housekeeping file directly under the root is not a skill. `README.md` has no directory
#     component, so returning it as a skill name made the guard look for `README.md/SKILL.md`,
#     fail to find it, and block an unrelated edit as UNKNOWN.
export FAKE_GIT_STORE="${tmp}/objects15"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
# The un-fixed code returns "README.md" as a skill name, so BOTH refs must exist or it
# short-circuits at the cat-file check and the case passes without exercising the fix.
store_exists "origin/main:.agents/skills/README.md" "housekeeping"
store_exists "HEAD:.agents/skills/README.md" "housekeeping"
mkdir -p "${tmp}/.agents/skills"
if CHANGED_PATHS=".agents/skills/README.md"$'\n' run_guard; then :; else
  rc=$?
  fail "root-level housekeeping file: rc=${rc} want=0 (it names no skill)"
fi
pass "a file directly under the skill root names no skill"

# 17. CRLF line endings are valid in a committed SKILL.md. Leaving the trailing CR on made the
#     first line differ from `---`, so front matter was never entered and a synced skill read as
#     having no provenance — which, under case 6's semantics, now means it would be EDITABLE.
new_case objects16 crlf \
  $'---\r\nmetadata:\r\n  github-repo: https://github.com/devantler-tech/agent-skills\r\n---\r\n'
if out="$(CHANGED_PATHS=".agents/skills/crlf/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "CRLF SKILL.md: expected a refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "CRLF SKILL.md: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "devantler-tech/agent-skills" || fail "CRLF: upstream should be named cleanly"
fi
pass "a CRLF SKILL.md still yields provenance"

# 18. A repository-root skill root (`.`) still matches. Normalising only `./` left the prefix as
#     `./`, while git emits `synced/SKILL.md` with no prefix at all — so this valid configuration
#     matched nothing and the guard exited 0 having checked nothing.
export FAKE_GIT_STORE="${tmp}/objects17"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/rootskill"
store_exists "origin/main:rootskill" "dir"
store_exists "HEAD:rootskill" "dir"
store_exists "origin/main:rootskill/SKILL.md" \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if SKILL_ROOT="." CHANGED_PATHS="rootskill/SKILL.md"$'\n' run_guard; then
  fail "repo-root skill root: expected a refusal, got success (fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "repo-root skill root: rc=${rc} want=1"
fi
pass "a repository-root skill root is normalised and still refuses"

# 19. An indented comment inside the metadata mapping must not fix the direct-child level. A
#     four-space comment above a two-space `github-repo` made the real key look like a non-child,
#     so provenance read empty — which now means "local", i.e. a silent pass on a synced skill.
new_case objects18 commented2 \
  $'---\nmetadata:\n    # upstream ownership, deliberately indented deeper than the key below\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/commented2/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "deep comment in metadata: expected a refusal, got success (fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "deep comment in metadata: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "devantler-tech/agent-skills" || fail "deep comment: upstream should be named"
fi
pass "an indented comment does not fix the metadata child level"

# 20. The action must PIN the CHANGED_PATHS test seam empty. A composite step inherits workflow-
#     and job-level env, so a consumer defining that name would have its value trusted instead of
#     the real diff, and any value outside the skill root makes the guard skip every edit.
if command -v yq >/dev/null 2>&1; then
  seam="$(yq '.runs.steps[0].env.CHANGED_PATHS // "MISSING"' "${root}/guard-installed-skill-edits/action.yaml")"
  [ "${seam}" = "" ] || [ "${seam}" = '""' ] || fail "action.yaml must pin CHANGED_PATHS empty, got: ${seam}"
  pass "action.yaml fences the CHANGED_PATHS test seam"
else
  echo "SKIP: yq unavailable, cannot assert the CHANGED_PATHS fence"
fi


# 22. A COLUMN-ZERO comment between `metadata:` and its `github-repo` child must not close the
#     mapping. A comment's first character is not a space or tab, so it matched the
#     top-level-key branch, set in_meta=0, and the direct child was then ignored — provenance
#     read empty, empty means "local", and the guard PERMITTED a hand-edit to a synced skill.
#     Case 19 above pins the INDENTED form; this pins the column-zero one, which took the
#     opposite path through the parser and was the one that failed open.
new_case objects22 commented0 \
  $'---\nmetadata:\n# upstream ownership, at column zero\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/commented0/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "column-zero comment in metadata: expected a refusal, got success (fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "column-zero comment in metadata: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "devantler-tech/agent-skills" || fail "column-zero comment: upstream should be named"
fi
pass "a column-zero comment does not close the metadata mapping"

# 23. NEGATIVE CONTROL for 22: a real top-level key after `metadata:` must STILL close the
#     mapping, so a `github-repo` under some later key is not read as provenance. Without this,
#     "skip comment lines" could be over-applied into "never close the mapping", which would
#     make every skill look synced and block legitimate local edits.
new_case objects23 closedmeta \
  $'---\nmetadata:\nother:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/closedmeta/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "a real top-level key must still close metadata (local skill), rc=${rc} want=0"
fi
pass "a real top-level key still closes the metadata mapping"

# 23-bis. MALFORMED YAML IS UNKNOWN, NOT LOCAL. This fixture is what case 23 used to carry: a
#     child indented under the SCALAR `other: 1`, which no YAML parser accepts ("mapping values
#     are not allowed in this context"). The line-oriented parser tolerated it and returned the
#     LOCAL verdict, which permits the edit — a guess about a document nobody can read. Failing
#     closed is the only defensible answer.
new_case objects23bis malformedmeta \
  $'---\nmetadata:\nother: 1\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/malformedmeta/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "malformed YAML: expected UNKNOWN, got success (a guess about an unparseable document)"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "malformed YAML: rc=${rc} want=2"
fi
pass "malformed front matter is UNKNOWN, never local"
# 24. NO CHECKOUT is UNKNOWN, never a clean pass. Without an `actions/checkout` step every path
#     is absent, so the missing-root no-op fired and this REQUIRED guard exited 0 having
#     evaluated nothing — the same "valid input -> zero matches -> exit 0" fail-open the diff
#     check already refuses for an unresolvable commit.
#
#     The stub returns `false` and exits 0 here, exactly as real git does in a bare repository:
#     a guard testing the exit status rather than the printed VALUE would still pass this.
export FAKE_GIT_STORE="${tmp}/objects24"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
touch "${FAKE_GIT_STORE}/not_worktree"
rm -rf "${tmp}/.agents"
if out="$(SKILL_ROOT=".agents/skills" BASE_SHA="b" HEAD_SHA="h" run_guard 2>&1)"; then
  fail "no work tree: expected UNKNOWN, got success (fail-open)"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "no work tree: rc=${rc} want=2"
  printf '%s' "${out}" | grep -q "not inside a git work tree" || fail "no work tree: should say why"
fi
rm -f "${FAKE_GIT_STORE}/not_worktree"
pass "a missing work tree is UNKNOWN, not a clean pass"

# 21. Repository-root mode must not treat every top-level directory as a skill.
#     With the documented `skill-root: .` the first path component of every changed file is
#     a skill candidate, so editing `.github/workflows/ci.yaml` selected `.github` — present
#     in both trees, no SKILL.md — and the guard failed an unrelated PR with UNKNOWN. That
#     fires on essentially every PR in a root-mode consumer.
export FAKE_GIT_STORE="${tmp}/objects25"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
store_exists "origin/main:.github" "dir"
store_exists "HEAD:.github" "dir"
store_exists "origin/main:.github/workflows/ci.yaml" "on: push"
if out="$(SKILL_ROOT="." CHANGED_PATHS=".github/workflows/ci.yaml"$'\n' run_guard 2>&1)"; then :; else
  rc=$?
  fail "root mode: a non-skill top-level dir must not block: rc=${rc} want=0 — got: ${out}"
fi
pass "root mode: a non-skill top-level directory is not a skill"

# 21b. Control for 21: root mode must STILL refuse a genuine synced skill. Without this,
#      case 21 would also pass if root mode had simply stopped checking anything.
export FAKE_GIT_STORE="${tmp}/objects26"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
store_exists "origin/main:synced" "dir"
store_exists "HEAD:synced" "dir"
store_exists "origin/main:synced/SKILL.md" \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(SKILL_ROOT="." CHANGED_PATHS="synced/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "control: root mode should still refuse a synced skill"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "control root mode: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "devantler-tech/agent-skills" || fail "control root mode: should name upstream"
fi
pass "control: root mode still refuses a synced skill"

# 22. A root present in the referenced TREES but absent from the CHECKOUT must still be
#     checked. Every decision this guard makes reads git objects, so asking `-d` about the
#     worktree tested something the script does not use: a sparse checkout that omits the
#     root, or a step that removed it, exited 0 without examining the diff at all.
export FAKE_GIT_STORE="${tmp}/objects27"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
rm -rf "${tmp}/.agents"
store_exists "origin/main:.agents/skills/sparse" "dir"
store_exists "HEAD:.agents/skills/sparse" "dir"
store_exists "origin/main:.agents/skills/sparse/SKILL.md" \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/sparse/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "sparse checkout: expected a refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "sparse checkout: rc=${rc} want=1"
fi
pass "a root absent from the checkout but present in the trees is still checked"

# 22b. Control for 22: a root absent from BOTH trees is still a genuine no-op. Narrowing
#      must not turn "this repo has no skills" into a failing required gate.
export FAKE_GIT_STORE="${tmp}/objects28"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
rm -rf "${tmp}/.agents"
if out="$(run_guard 2>&1)"; then
  printf '%s' "${out}" | grep -q "nothing to check" || fail "control: should say nothing to check"
else
  rc=$?
  fail "control: a root absent from both trees should no-op: rc=${rc} want=0"
fi
pass "control: a root absent from both trees is still a no-op"

# 23. Flow-style metadata is the same key, and missing it FAILED OPEN: the line parser did
#     not enter the mapping, provenance read empty, and empty means LOCAL — so the guard
#     permitted a hand-edit to a synced skill, the one thing it exists to refuse.
new_case objects29 flow \
  $'---\nname: flow\nmetadata: {github-repo: "https://github.com/devantler-tech/agent-skills"}\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/flow/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "flow-style metadata: expected a refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "flow-style metadata: rc=${rc} want=1"
  printf '%s' "${out}" | grep -q "devantler-tech/agent-skills" || fail "flow-style: should name upstream"
fi
pass "flow-style metadata.github-repo is provenance"

# 23b. A flow mapping with no github-repo key genuinely records no provenance: that is the
#      LOCAL verdict, and a local skill stays editable.
new_case objects30 flowlocal \
  $'---\nmetadata: {version: 2, category: local}\n---\n'
if CHANGED_PATHS=".agents/skills/flowlocal/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "flow mapping without github-repo is LOCAL: rc=${rc} want=0"
fi
pass "a flow mapping with no github-repo is local"

# 23c. A NESTED flow mapping is not provenance. `metadata.source.github-repo` is a deeper key,
#      and case 12 already establishes that a deeper key is not provenance — so the skill is
#      LOCAL and stays editable. The line parser could not follow the nesting and had to fail
#      closed; a real parser answers the question.
new_case objects31 flownested \
  $'---\nmetadata: {source: {github-repo: https://github.com/someone/else}}\n---\n'
if CHANGED_PATHS=".agents/skills/flownested/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "nested flow mapping: a deeper key is not provenance, so local: rc=${rc} want=0"
fi
pass "a nested flow mapping is not provenance, and stays local"
# 23d. A flow mapping SPANNING LINES is still that mapping. The line parser saw an unterminated
#      `{` and had to fail closed; a real parser reads the continuation, finds the provenance,
#      and the edit is refused naming the upstream — the verdict that was always correct here.
new_case objects32 flowopen \
  $'---\nmetadata: {github-repo:\n  https://github.com/devantler-tech/agent-skills}\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/flowopen/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "multi-line flow mapping: expected refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "multi-line flow mapping: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "multi-line flow mapping: should name the upstream"
fi
pass "a flow mapping spanning lines is read, and its provenance refused"
# 23e. AN ANCHOR IS NOT A HIDING PLACE. `metadata: &meta` carries real provenance underneath;
#      the line parser could not follow the anchor and fell back to UNKNOWN, so a synced skill
#      merely looked undecidable. A real parser resolves it and the edit is refused.
new_case objects33 anchored \
  $'---\nmetadata: &meta\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/anchored/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "anchored metadata: expected refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "anchored metadata: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "anchored metadata: should name the upstream"
fi
pass "an anchored metadata mapping is resolved, and its provenance refused"
# 24. An UNREADABLE commit must not read as an absent skill root. `cat-file -e <sha>:<dir>`
#     fails identically for a missing commit and for a commit without that path, so under
#     the depth-1 default of actions/checkout both lookups fail, the "no root in either
#     commit" branch fires, and this REQUIRED guard exits 0 before reaching the diff or the
#     UNKNOWN checks — passing without evaluating a single edit.
export FAKE_GIT_STORE="${tmp}/objects34"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
rm -rf "${tmp}/.agents"
printf '%s\n' "origin/main" >"${FAKE_GIT_STORE}/unreadable_commits"
if out="$(CHANGED_PATHS=".agents/skills/anything/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "unreadable base commit: expected UNKNOWN, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "unreadable base commit: rc=${rc} want=2"
  printf '%s' "${out}" | grep -q "not present in this clone" || fail "unreadable base commit: should say why"
fi
rm -f "${FAKE_GIT_STORE}/unreadable_commits"
pass "an unreadable commit is UNKNOWN, not an absent skill root"

# 24b. Control for 24: with both commits readable and the root genuinely absent from both,
#      the no-op still stands. Without this, case 24 would also pass if the guard had simply
#      stopped no-opping at all.
export FAKE_GIT_STORE="${tmp}/objects35"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
rm -rf "${tmp}/.agents"
if out="$(run_guard 2>&1)"; then
  printf '%s' "${out}" | grep -q "nothing to check" || fail "control 24b: should say nothing to check"
else
  rc=$?
  fail "control 24b: readable commits with no root should no-op: rc=${rc} want=0"
fi
pass "control: readable commits with no root still no-op"


# 25. A QUOTED provenance key is the same key in valid YAML, and a plain-key-only match
#     cannot see it: the loop falls off the end, provenance reads EMPTY, and empty means
#     LOCAL — so the guard PERMITS a hand-edit to a synced skill, the one thing it exists
#     to refuse. This is the fourth legal spelling of this document to reach that same
#     fail-open, so the guard now treats any unreadable direct child as UNKNOWN.
new_case objects36 dquoted \
  $'---\nmetadata:\n  "github-repo": "https://github.com/devantler-tech/agent-skills"\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/dquoted/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "double-quoted provenance key: expected refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "double-quoted provenance key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "double-quoted provenance key: should name the upstream"
fi
pass "a double-quoted provenance key is READ and refused, naming the upstream"

# 25b. Single quotes are the same valid YAML, and must not need their own special case.
new_case objects37 squoted \
  $'---\nmetadata:\n  \'github-repo\': https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/squoted/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "single-quoted provenance key: expected refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "single-quoted provenance key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "single-quoted provenance key: should name the upstream"
fi
pass "a single-quoted provenance key is READ and refused, naming the upstream"

# 25c. CONTROL for 25/25b: a genuinely local skill — plain metadata children, no
#      github-repo — is still EDITABLE. Without this, both cases above would also pass if
#      the guard had simply started refusing every skill it was shown, which is the cheap
#      way to satisfy a fail-closed test and is not the fix.
new_case objects38 plainlocal \
  $'---\nname: plainlocal\nmetadata:\n  version: 1.2.3\n  tags: [a, b]\n---\n'
if CHANGED_PATHS=".agents/skills/plainlocal/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "control 25c: a plain local skill must stay editable: rc=${rc} want=0"
fi
pass "control: plain metadata children with no github-repo stay local"

# 26. A Git-valid path may CONTAIN a newline. Translating the -z diff to newline-delimited
#     text split such a path into two records: the first has no directory component below
#     the root and the second has lost the root prefix, so BOTH were ignored and an edit to
#     a provenanced skill exited 0. The diff is now consumed NUL-delimited end to end.
export FAKE_GIT_STORE="${tmp}/objects39"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
nl_dir=$'.agents/skills/sync\ned'
store_exists "origin/main:${nl_dir}" "dir"
store_exists "HEAD:${nl_dir}" "dir"
store_exists "origin/main:${nl_dir}/SKILL.md" \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
printf '%s\0' "${nl_dir}/SKILL.md" >"${FAKE_GIT_STORE}/diff_out"
if out="$(run_guard 2>&1)"; then
  fail "newline in path: expected refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "newline in path: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "newline in path: should name the upstream"
fi
rm -f "${FAKE_GIT_STORE}/diff_out"
pass "a changed path containing a newline is still matched to its skill"

# 26b. CONTROL for 26: the SAME fixture with an ordinary path is refused too, so case 26
#      cannot be satisfied by a reader that refuses whatever it fails to parse.
export FAKE_GIT_STORE="${tmp}/objects40"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
store_exists "origin/main:.agents/skills/ordinary" "dir"
store_exists "HEAD:.agents/skills/ordinary" "dir"
store_exists "origin/main:.agents/skills/ordinary/SKILL.md" \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
printf '%s\0' ".agents/skills/ordinary/SKILL.md" >"${FAKE_GIT_STORE}/diff_out"
if run_guard >/dev/null 2>&1; then
  fail "control 26b: an ordinary NUL-delimited path should still be refused"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "control 26b: rc=${rc} want=1"
fi
rm -f "${FAKE_GIT_STORE}/diff_out"
pass "control: an ordinary NUL-delimited path is still refused"

# 27. THE FLOW BRANCH NEEDS THE SAME RULE, or the class is only half closed. Case 25 fixed the
#     block mapping; `metadata: {"github-repo": ...}` is the same key again in flow style, and a
#     plain-entry-only match fell through to the LOCAL case — the identical silent permit, reached
#     by the fifth spelling of this one document.
new_case objects41 flowquoted \
  $'---\nmetadata: {"github-repo": "https://github.com/devantler-tech/agent-skills"}\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/flowquoted/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "quoted flow key: expected refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "quoted flow key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "quoted flow key: should name the upstream"
fi
pass "a quoted key in a flow mapping is READ and refused, naming the upstream"

# 27b. CONTROL: an EMPTY flow mapping genuinely records no provenance and must stay LOCAL. Without
#      this, case 27 would also pass if every flow mapping had simply become UNKNOWN.
export FAKE_GIT_STORE="${tmp}/objects42"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/flowempty"
store_exists "origin/main:.agents/skills/flowempty" "dir"
store_exists "HEAD:.agents/skills/flowempty" "dir"
store_exists "origin/main:.agents/skills/flowempty/SKILL.md" $'---\nmetadata: { }\n---\n'
if CHANGED_PATHS=".agents/skills/flowempty/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "control 27b: an empty flow mapping must stay local: rc=${rc} want=0"
fi
pass "control: an empty flow mapping stays local"

# 27c. CONTROL: a plain flow entry that is simply a DIFFERENT key must also stay local — the rule
#      fires on unreadable entries, not on every entry that is not github-repo.
new_case objects43 flowother \
  $'---\nmetadata: {version: 1.2.3, tags: abc}\n---\n'
if CHANGED_PATHS=".agents/skills/flowother/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "control 27c: plain non-provenance flow keys must stay local: rc=${rc} want=0"
fi
pass "control: plain non-provenance flow keys stay local"

# 28. THE PARENT KEY HAS THE SAME SPELLINGS AS THE CHILD. `metadata :` (whitespace before the
#     mapping colon) is valid YAML and did not set in_meta, so the plain `github-repo` child below
#     it was ignored, provenance read empty, and empty means LOCAL.
new_case objects44 spacedparent \
  $'---\nmetadata :\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/spacedparent/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "spaced parent key: expected refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "spaced parent key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "spaced parent key: should name the upstream"
fi
pass "a whitespace-before-colon parent key is read, not ignored"

# 28b. A QUOTED parent key is the same key again.
new_case objects45 quotedparent \
  $'---\n"metadata":\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/quotedparent/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "quoted parent key: expected refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "quoted parent key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "quoted parent key: should name the upstream"
fi
pass "a quoted parent key is read, not ignored"

# 28c. `github-repo : <url>` — whitespace before the CHILD's colon. This one was the nastiest,
#      because the previous fix's plain-key pattern MATCHED it as "some other key" and continued,
#      so the guard classified the skill local while looking like it had read the line.
new_case objects46 spacedchild \
  $'---\nmetadata:\n  github-repo : https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/spacedchild/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "spaced child key: expected refusal, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "spaced child key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "spaced child key: should name the upstream"
fi
pass "a whitespace-before-colon child key is read, not treated as another key"

# 28d. A genuinely UNREADABLE key still fails closed. An unterminated quoted key is not a key
#      this parser can name, so it must be UNKNOWN — not local, and not silently skipped.
new_case objects47 unterminated \
  $'---\nmetadata:\n  "github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/unterminated/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "unterminated quoted key: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "unterminated quoted key: rc=${rc} want=2"
fi
pass "an unreadable key still fails closed as UNKNOWN"

# 28e. CONTROL for the whole normalisation: a plain local skill with ordinary spellings is still
#      editable. Normalising keys must not turn every skill into a refusal or an UNKNOWN.
new_case objects48 normal \
  $'---\nname: normal\ndescription: an ordinary local skill\nmetadata:\n  version: 2\n---\n'
if CHANGED_PATHS=".agents/skills/normal/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "control 28e: an ordinary local skill must stay editable: rc=${rc} want=0"
fi
pass "control: an ordinary local skill stays editable under key normalisation"

# 29. AN ENCODED KEY IS THE KEY. `"github-repo"` resolves to `github-repo`, so this is
#     ordinary provenance and the edit is refused naming the upstream. The line parser compared
#     the literal spelling, read it as an unrelated key, and returned empty — and empty means
#     LOCAL, so it silently permitted the edit. A real parser decodes the escape.
new_case objects49 escaped \
  $'---\nmetadata:\n  "github\\u002drepo": https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/escaped/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "escaped key: expected refusal, got success (this was the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "escaped key: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "escaped key: should name the upstream"
fi
pass "an escaped quoted key is decoded, and its provenance refused"
# 30. YAML NULL NAMES NO UPSTREAM — and refusing it is a FALSE REFUSAL shipped to every consumer.
#     `github-repo: null` is a valid way for a local skill to carry the key while recording no
#     provenance; returning the literal token made the guard refuse every edit and print
#     `upstream: null`.
for nul in 'null' '~' 'Null'; do
  export FAKE_GIT_STORE="${tmp}/objects50-${nul}"
  mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
  mkdir -p "${tmp}/.agents/skills/nullprov"
  store_exists "origin/main:.agents/skills/nullprov" "dir"
  store_exists "HEAD:.agents/skills/nullprov" "dir"
  store_exists "origin/main:.agents/skills/nullprov/SKILL.md" \
    "---"$'\n'"metadata:"$'\n'"  github-repo: ${nul}"$'\n'"---"$'\n'
  if CHANGED_PATHS=".agents/skills/nullprov/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
    rc=$?
    fail "null provenance (${nul}): must be local: rc=${rc} want=0"
  fi
done
pass "YAML null provenance (null / ~ / Null) is absent, not an upstream"

# 30b. A comment-only value names no upstream either.
new_case objects51 commentprov \
  $'---\nmetadata:\n  github-repo: # intentionally local\n---\n'
if CHANGED_PATHS=".agents/skills/commentprov/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "comment-only provenance: must be local: rc=${rc} want=0"
fi
pass "a comment-only provenance value is absent, not an upstream"

# 30c. CONTROL for 30: a URL carrying a FRAGMENT keeps its tail. `#` opens a comment only after
#      whitespace, so a narrow strip must not truncate `https://example.test/x#y`.
new_case objects52 fragment \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills#frag\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/fragment/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "fragment URL: expected refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "fragment URL: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "agent-skills#frag" \
    || fail "fragment URL: the fragment must survive the comment strip"
fi
pass "control: a '#' fragment inside a URL survives the comment strip"

# 31. SPLITTING EVERY COMMA IS A FALSE REFUSAL. `{tags: [a, b]}` is ordinary local metadata; an
#     unconditional split made the second fragment unreadable, so the guard reported UNKNOWN and
#     EVERY legitimate edit to that skill exited 2.
new_case objects53 flowseq \
  $'---\nmetadata: {tags: [a, b], version: 1}\n---\n'
if CHANGED_PATHS=".agents/skills/flowseq/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "flow sequence comma: must stay local: rc=${rc} want=0"
fi
pass "a comma inside a flow sequence does not split the entry"

# 31b. The same for a comma inside a QUOTED scalar.
new_case objects54 flowquote \
  $'---\nmetadata: {note: "a,b"}\n---\n'
if CHANGED_PATHS=".agents/skills/flowquote/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "flow quoted comma: must stay local: rc=${rc} want=0"
fi
pass "a comma inside a quoted flow scalar does not split the entry"

# 31c. CONTROL for 31: provenance is STILL FOUND past a comma-bearing entry, so the splitter did
#      not simply stop parsing. Without this, 31/31b would also pass if flow parsing had been
#      disabled altogether.
new_case objects55 flowfind \
  $'---\nmetadata: {tags: [a, b], github-repo: https://github.com/devantler-tech/agent-skills}\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/flowfind/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "flow find past comma: expected refusal, got success"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "flow find past comma: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "flow find past comma: should name the upstream"
fi
pass "control: provenance is still found in an entry after a comma-bearing one"

# 31d. An UNTERMINATED quote inside a flow mapping is undecidable, not local.
new_case objects56 flowbadquote \
  $'---\nmetadata: {note: "a,b}\n---\n'
if CHANGED_PATHS=".agents/skills/flowbadquote/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "unterminated flow quote: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "unterminated flow quote: rc=${rc} want=2"
fi
pass "an unterminated quote in a flow mapping is UNKNOWN, not local"

# 32. AN EXPLICIT NULL PARENT IS AN EMPTY MAPPING, NOT AN UNREADABLE ONE. `metadata: null`, `Null`,
#     `NULL` and `~` are valid ways to write a metadata key holding nothing, so they record no
#     provenance and the skill is LOCAL — exactly as `metadata: {}` already was, and exactly as
#     `github-repo: null` already was one level down. They previously fell through to the scalar
#     branch and became UNKNOWN: a false refusal, and an inconsistency between three spellings of
#     the same YAML.
for nul in 'null' 'Null' 'NULL' '~'; do
  new_case "objects57-${nul}" nullparent "---"$'\n'"metadata: ${nul}"$'\n'"---"$'\n'
  if CHANGED_PATHS=".agents/skills/nullparent/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
    rc=$?
    fail "null metadata parent (${nul}): must be local: rc=${rc} want=0"
  fi
done
pass "an explicit null metadata parent is an empty mapping, not UNKNOWN"

# 32b. The same with a trailing comment.
new_case objects58 nullparentc $'---\nmetadata: null # nothing here\n---\n'
if CHANGED_PATHS=".agents/skills/nullparentc/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "null metadata parent with comment: must be local: rc=${rc} want=0"
fi
pass "a null metadata parent with a trailing comment is local"

# 32c. CONTROL for 32: an ANCHORED metadata parent still carries real provenance, so the null
#      carve-out must not swallow it. This is the case that proves "treat null as absent" was
#      not over-applied into "treat any non-mapping remainder as absent".
new_case objects59 anchorparent \
  $'---\nmetadata: &meta\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/anchorparent/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "control 32c: an anchored metadata parent carries provenance and must be refused"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "control 32c: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" \
    || fail "control 32c: should name the upstream"
fi
pass "control: an anchored metadata parent is resolved, not swallowed by the null carve-out"
# 32d. CONTROL for 32: a value merely STARTING with 'null' is not YAML null — but it is still a
#      SCALAR, and a scalar `metadata` has no `github-repo` child at all. So the skill records no
#      provenance and stays editable. What this control actually pins is that the null handling
#      keys on the parsed VALUE and never on a string prefix: were `nullify-me` matched as null
#      by prefix, the same bug would misread a real provenance value elsewhere.
new_case objects60 nullish $'---\nmetadata: nullify-me\n---\n'
if CHANGED_PATHS=".agents/skills/nullish/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "control 32d: a scalar metadata has no github-repo child, so local: rc=${rc} want=0"
fi

# 33. A MERGE ALIAS IS PROVENANCE. `metadata:\n  <<: *upstream` pulls the key in by reference, so
#     the skill IS synced. The line parser read `<<` as an unrelated key and returned empty, and
#     empty means LOCAL — it silently permitted the edit.
new_case objects61 merged \
  $'---\nup: &u\n  github-repo: https://github.com/devantler-tech/agent-skills\nmetadata:\n  <<: *u\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/merged/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "merge alias: expected refusal, got success (this was the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "merge alias: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" || fail "merge alias: should name the upstream"
fi
pass "a merge alias is resolved, and its provenance refused"

# 34. A QUOTED EMPTY VALUE WITH A TRAILING COMMENT records no provenance. The comment sat AFTER the
#     closing quote, so a strip that skipped quoted values left the comment attached and the whole
#     text read as a nonempty upstream — every edit falsely refused.
new_case objects62 quotedempty $'---\nmetadata:\n  github-repo: "" # intentionally local\n---\n'
if CHANGED_PATHS=".agents/skills/quotedempty/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "quoted empty + comment: must be local: rc=${rc} want=0"
fi
pass "a quoted empty value with a trailing comment is absent provenance"

# 35. A BRACE INSIDE A QUOTED SCALAR IS NOT NESTING. A raw substring test for `{` mistook it for a
#     nested mapping and returned UNKNOWN, blocking every edit to an ordinary local skill.
new_case objects63 bracequote $'---\nmetadata: {note: "literal { brace"}\n---\n'
if CHANGED_PATHS=".agents/skills/bracequote/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "quoted brace: must stay local: rc=${rc} want=0"
fi
pass "a brace inside a quoted flow scalar is not nesting"

# 36. A MULTILINE PROVENANCE VALUE is still that value. Block YAML may put the scalar on the next
#     line; the line parser saw an empty value on the key line and treated it as absent — LOCAL,
#     silently permitting the edit to a synced skill.
new_case objects64 multiline \
  $'---\nmetadata:\n  github-repo:\n    https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/multiline/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "multiline value: expected refusal, got success (this was the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "multiline value: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" || fail "multiline value: should name the upstream"
fi
pass "a provenance value on the following line is read, and refused"

# 37. AN INDENTED ROOT MAPPING is still the root. Valid YAML may indent every top-level key; a
#     parser that only treats column zero as top level never found `metadata`, returned empty, and
#     empty means LOCAL.
new_case objects65 indentedroot \
  $'---\n  metadata:\n    github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/indentedroot/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "indented root: expected refusal, got success (this was the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 1 ] || fail "indented root: rc=${rc} want=1"
  printf '%s' "${out}" | grep -qF -- "devantler-tech/agent-skills" || fail "indented root: should name the upstream"
fi
pass "an indented root mapping is still the root"

# 38. CONTROL for the yq migration: with no YAML parser available the guard is UNDECIDABLE, never
#     local. A missing dependency must not silently degrade into permitting every edit — that is
#     the fail-open the whole rewrite exists to remove, and it would be the easiest one to ship.
#
#     The PATH is built by SYMLINKING exactly the externals the guard uses, deliberately omitting
#     yq — not by trimming directories off the real PATH. Trimming is environment-dependent and was
#     measured failing: yq is under /opt/homebrew/bin on macOS but /usr/bin on a GitHub runner, so a
#     "reduced" PATH that dropped one still contained the other. The fixture assertion below is what
#     caught that, and it stays: a control whose setup silently stops holding is worse than none.
new_case objects66 noyq \
  $'---\nmetadata:\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
mkdir -p "${tmp}/noyqbin"
# `bash` is in the list because run_guard re-execs it through `env -i` with this PATH: without it
# the control exits 127 — the shell missing, not the parser — which is the wrong failure entirely.
for _t in env bash git mktemp rm cat tr grep; do
  _src="$(command -v "${_t}" || true)"
  [ -n "${_src}" ] || fail "control 38 fixture: cannot locate ${_t} to build the parser-free PATH"
  ln -sf "${_src}" "${tmp}/noyqbin/${_t}"
done
noyq_path="${tmp}/noyqbin"
PATH="${noyq_path}" command -v yq >/dev/null 2>&1 \
  && fail "control 38 fixture: yq is still reachable on the parser-free PATH"
# Prove the reduced PATH can still RUN the harness, not merely that some tool is present. Each
# missing external here surfaced as rc=127 — the shell, then env — which is indistinguishable from
# a wrong verdict unless the fixture asserts its own viability first.
_probe_rc=0
PATH="${noyq_path}" env -i PATH="${noyq_path}" bash -c 'exit 7' >/dev/null 2>&1 || _probe_rc=$?
[ "${_probe_rc}" -eq 7 ] || fail "control 38 fixture: the parser-free PATH cannot run the harness (rc=${_probe_rc}), so a 127 would masquerade as a verdict"
if PATH="${noyq_path}" CHANGED_PATHS=".agents/skills/noyq/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "control 38: with no yq the guard must be UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "control 38: rc=${rc} want=2"
fi
pass "control: an unavailable YAML parser is UNKNOWN, never local"
echo "ALL PASS"
