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
if ! SKILL_ROOT=".agents/skills" BASE_SHA="" HEAD_SHA="" run_guard; then
  fail "missing skill root should no-op"
fi
pass "missing skill root is a no-op"

# 3. New skill directory is allowed
mkdir -p "${tmp}/.agents/skills/brand-new"
printf '%s\n' ".agents/skills/brand-new/SKILL.md" >"${tmp}/lstree-head"
export FAKE_GIT_STORE="${tmp}/objects2"
mkdir -p "${FAKE_GIT_STORE}/lstree" "${FAKE_GIT_STORE}/show"
printf '%s\n' ".agents/skills/brand-new/SKILL.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if ! CHANGED_PATHS=".agents/skills/brand-new/SKILL.md"$'\n' run_guard; then
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
if CHANGED_PATHS=".agents/skills/empty/SKILL.md"$'\n' run_guard; then
  fail "empty provenance: expected unknown"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "empty provenance: rc=${rc} want=2"
fi
pass "empty provenance at BASE is UNKNOWN"

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
if ! CHANGED_PATHS=".agents/skills/retired/SKILL.md"$'\n' run_guard; then
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
if CHANGED_PATHS=".agents/skills/toplevel/SKILL.md"$'\n' run_guard; then
  fail "top-level github-repo: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "top-level github-repo: rc=${rc} want=2 (must not be a refusal)"
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
if CHANGED_PATHS=".agents/skills/nested/SKILL.md"$'\n' run_guard; then
  fail "nested provenance: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "nested provenance: rc=${rc} want=2 (must not be a refusal)"
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
if CHANGED_PATHS=".agents/skills/decoy/SKILL.md"$'\n' run_guard; then
  fail "decoy key: expected UNKNOWN, got success"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "decoy key: rc=${rc} want=2 (metadataX must not open the mapping)"
fi
pass "control: metadataX: does not open the metadata mapping"

echo "ALL PASS"
