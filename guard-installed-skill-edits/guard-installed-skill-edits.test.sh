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

# 8. Retiring a skill is allowed
export FAKE_GIT_STORE="${tmp}/objects7"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills"
: >"${FAKE_GIT_STORE}/lstree/HEAD"
if ! CHANGED_PATHS=".agents/skills/retired/SKILL.md"$'\n' run_guard; then
  fail "retiring a skill should be allowed"
fi
pass "retiring a skill is allowed"

# 9. SKILL.md gone at BASE while the directory remains is UNKNOWN
export FAKE_GIT_STORE="${tmp}/objects8"
mkdir -p "${FAKE_GIT_STORE}/show" "${FAKE_GIT_STORE}/lstree"
mkdir -p "${tmp}/.agents/skills/orphan"
store_exists "origin/main:.agents/skills/orphan" "dir"
printf '%s\n' ".agents/skills/orphan/README.md" >"${FAKE_GIT_STORE}/lstree/HEAD"
if CHANGED_PATHS=".agents/skills/orphan/README.md"$'\n' run_guard; then
  fail "orphan dir: expected unknown"
else
  rc=$?
  [ "${rc}" -eq 2 ] || fail "orphan dir: rc=${rc} want=2"
fi
pass "SKILL.md gone at BASE while directory remains is UNKNOWN"

echo "ALL PASS"
