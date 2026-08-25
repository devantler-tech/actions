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
    key="${spec//\//_}"
    key="${key//:/_}"
    [ -f "${store}/show/${key}" ] || exit 1
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
echo "ALL PASS"
