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
export FAKE_GIT_STORE="${tmp}/objects11"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/nested"
store_exists "origin/main:.agents/skills/nested" "dir"
store_exists "HEAD:.agents/skills/nested" "dir"
store_exists "origin/main:.agents/skills/nested/SKILL.md" \
  $'---\nmetadata:\n  source:\n    github-repo: https://github.com/someone/else\n---\n'
if CHANGED_PATHS=".agents/skills/nested/SKILL.md"$'\n' run_guard; then :; else
  rc=$?
  fail "metadata.source.github-repo is not provenance: rc=${rc} want=0 — no provenance means LOCAL, and a local skill is editable"
fi
pass "metadata.source.github-repo is not provenance"

# 12b. Control for 12: a genuine DIRECT metadata.github-repo, in a file whose front matter
#      is otherwise shaped identically, is still detected and still refused. Without this,
#      case 12 would also pass if the parser had simply stopped reading provenance at all.
export FAKE_GIT_STORE="${tmp}/objects11b"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/nested"
store_exists "origin/main:.agents/skills/nested" "dir"
store_exists "HEAD:.agents/skills/nested" "dir"
store_exists "origin/main:.agents/skills/nested/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects12"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/commented"
store_exists "origin/main:.agents/skills/commented" "dir"
store_exists "HEAD:.agents/skills/commented" "dir"
store_exists "origin/main:.agents/skills/commented/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects12b"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/decoy"
store_exists "origin/main:.agents/skills/decoy" "dir"
store_exists "HEAD:.agents/skills/decoy" "dir"
store_exists "origin/main:.agents/skills/decoy/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects14"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/ways-of-working"
store_exists "origin/main:.agents/skills/ways-of-working" "dir"
store_exists "HEAD:.agents/skills/ways-of-working" "dir"
store_exists "origin/main:.agents/skills/ways-of-working/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects16"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/crlf"
store_exists "origin/main:.agents/skills/crlf" "dir"
store_exists "HEAD:.agents/skills/crlf" "dir"
store_exists "origin/main:.agents/skills/crlf/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects18"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/commented2"
store_exists "origin/main:.agents/skills/commented2" "dir"
store_exists "HEAD:.agents/skills/commented2" "dir"
store_exists "origin/main:.agents/skills/commented2/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects22"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/commented0"
store_exists "origin/main:.agents/skills/commented0" "dir"
store_exists "HEAD:.agents/skills/commented0" "dir"
store_exists "origin/main:.agents/skills/commented0/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects23"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/closedmeta"
store_exists "origin/main:.agents/skills/closedmeta" "dir"
store_exists "HEAD:.agents/skills/closedmeta" "dir"
store_exists "origin/main:.agents/skills/closedmeta/SKILL.md" \
  $'---\nmetadata:\nother: 1\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/closedmeta/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "a real top-level key must still close metadata (local skill), rc=${rc} want=0"
fi
pass "a real top-level key still closes the metadata mapping"

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
export FAKE_GIT_STORE="${tmp}/objects29"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/flow"
store_exists "origin/main:.agents/skills/flow" "dir"
store_exists "HEAD:.agents/skills/flow" "dir"
store_exists "origin/main:.agents/skills/flow/SKILL.md" \
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
export FAKE_GIT_STORE="${tmp}/objects30"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/flowlocal"
store_exists "origin/main:.agents/skills/flowlocal" "dir"
store_exists "HEAD:.agents/skills/flowlocal" "dir"
store_exists "origin/main:.agents/skills/flowlocal/SKILL.md" \
  $'---\nmetadata: {version: 2, category: local}\n---\n'
if CHANGED_PATHS=".agents/skills/flowlocal/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then :; else
  rc=$?
  fail "flow mapping without github-repo is LOCAL: rc=${rc} want=0"
fi
pass "a flow mapping with no github-repo is local"

# 23c. A NESTED flow mapping is undecidable for a line parser. Undecidable must be UNKNOWN,
#      never local — collapsing it into the empty/local verdict is the same fail-open.
export FAKE_GIT_STORE="${tmp}/objects31"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/flownested"
store_exists "origin/main:.agents/skills/flownested" "dir"
store_exists "HEAD:.agents/skills/flownested" "dir"
store_exists "origin/main:.agents/skills/flownested/SKILL.md" \
  $'---\nmetadata: {source: {github-repo: https://github.com/someone/else}}\n---\n'
if out="$(CHANGED_PATHS=".agents/skills/flownested/SKILL.md"$'\n' run_guard 2>&1)"; then
  fail "nested flow mapping: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "nested flow mapping: rc=${rc} want=2"
fi
pass "a nested flow mapping is UNKNOWN, not local"

# 23d. An UNTERMINATED flow mapping spans lines and is equally undecidable.
export FAKE_GIT_STORE="${tmp}/objects32"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/flowopen"
store_exists "origin/main:.agents/skills/flowopen" "dir"
store_exists "HEAD:.agents/skills/flowopen" "dir"
store_exists "origin/main:.agents/skills/flowopen/SKILL.md" \
  $'---\nmetadata: {github-repo:\n  https://github.com/devantler-tech/agent-skills}\n---\n'
if CHANGED_PATHS=".agents/skills/flowopen/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "unterminated flow mapping: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "unterminated flow mapping: rc=${rc} want=2"
fi
pass "an unterminated flow mapping is UNKNOWN, not local"

# 23e. `metadata: &anchor` / `*alias` is a metadata key this parser cannot follow. Same rule.
export FAKE_GIT_STORE="${tmp}/objects33"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/anchored"
store_exists "origin/main:.agents/skills/anchored" "dir"
store_exists "HEAD:.agents/skills/anchored" "dir"
store_exists "origin/main:.agents/skills/anchored/SKILL.md" \
  $'---\nmetadata: &meta\n  github-repo: https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/anchored/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "anchored metadata: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "anchored metadata: rc=${rc} want=2"
fi
pass "an anchored metadata mapping is UNKNOWN, not local"


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
export FAKE_GIT_STORE="${tmp}/objects36"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/dquoted"
store_exists "origin/main:.agents/skills/dquoted" "dir"
store_exists "HEAD:.agents/skills/dquoted" "dir"
store_exists "origin/main:.agents/skills/dquoted/SKILL.md" \
  $'---\nmetadata:\n  "github-repo": "https://github.com/devantler-tech/agent-skills"\n---\n'
if CHANGED_PATHS=".agents/skills/dquoted/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "double-quoted provenance key: expected UNKNOWN, got success (this is the fail-open)"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "double-quoted provenance key: rc=${rc} want=2"
fi
pass "a double-quoted provenance key is UNKNOWN, not local"

# 25b. Single quotes are the same valid YAML, and must not need their own special case.
export FAKE_GIT_STORE="${tmp}/objects37"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/squoted"
store_exists "origin/main:.agents/skills/squoted" "dir"
store_exists "HEAD:.agents/skills/squoted" "dir"
store_exists "origin/main:.agents/skills/squoted/SKILL.md" \
  $'---\nmetadata:\n  \'github-repo\': https://github.com/devantler-tech/agent-skills\n---\n'
if CHANGED_PATHS=".agents/skills/squoted/SKILL.md"$'\n' run_guard >/dev/null 2>&1; then
  fail "single-quoted provenance key: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "single-quoted provenance key: rc=${rc} want=2"
fi
pass "a single-quoted provenance key is UNKNOWN, not local"

# 25c. CONTROL for 25/25b: a genuinely local skill — plain metadata children, no
#      github-repo — is still EDITABLE. Without this, both cases above would also pass if
#      the guard had simply started refusing every skill it was shown, which is the cheap
#      way to satisfy a fail-closed test and is not the fix.
export FAKE_GIT_STORE="${tmp}/objects38"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/plainlocal"
store_exists "origin/main:.agents/skills/plainlocal" "dir"
store_exists "HEAD:.agents/skills/plainlocal" "dir"
store_exists "origin/main:.agents/skills/plainlocal/SKILL.md" \
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
echo "ALL PASS"
