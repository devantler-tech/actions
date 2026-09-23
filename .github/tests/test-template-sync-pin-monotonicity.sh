#!/usr/bin/env bash

# Template sync must never move a consumer backwards on a devantler-tech/actions pin (#1239).
# devantler-tech/wedding-app#332 was a green sync PR that replaced three v13.6.0 pins with the
# template's older v13.5.1 ones: both pins were approved, so only ORDER relative to the target
# could catch it. The signing helper therefore orders every changed pin against the target's with
# GitHub's compare API (commit ancestry, not the mutable `# vX.Y.Z` comment), keeps the target's
# line wherever the template's pin is behind or diverged, and signs only that corrected tree.
#
# This drives the real helper against git fixtures and a fake `gh` that answers the compare API
# from a table and builds trees exactly as GitHub does (from the posted content), so the signed
# tree is checked byte-for-byte against an independently constructed expectation.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/.github/scripts/replace-template-sync-commit.sh"

# Real release commits of devantler-tech/actions: v13.5.1 is an ancestor of v13.6.0.
v1351="a147ead8b8bc937fbfb1974e3698c7e32f95517d"
v1360="759ff9b2526cd1b142b49c5dc1616118a1ef44d9"
fork="cccccccccccccccccccccccccccccccccccccccc"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$helper" ]] || fail "template-sync signing helper is missing or not executable"

test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

export SIGNED_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

write_fake_gh() {
  cat >"$1/gh" <<'FAKE_GH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == "api" ]] || exit 91
shift
method=GET
endpoint=""
while (($#)); do
  case "$1" in
    -X|--method) method="$2"; shift 2 ;;
    --input) [[ "$2" == "-" ]] || exit 92; shift 2 ;;
    -H|--header) shift 2 ;;
    --*) exit 90 ;;
    *) [[ -z "$endpoint" ]] || exit 93; endpoint="$1"; shift ;;
  esac
done
printf '%s %s\n' "$method" "$endpoint" >>"$FAKE_GH_LOG"

case "$method $endpoint" in
  "GET repos/devantler-tech/actions/compare/"*)
    range="${endpoint#repos/devantler-tech/actions/compare/}"
    status="$(sed -n "s/^${range} //p" "$FAKE_COMPARE")"
    [[ -n "$status" ]] || exit 97
    jq -n --arg s "$status" '{status:$s}'
    ;;
  "GET repos/example/consumer/git/ref/heads/chore/template-sync_deadbee")
    if [[ -f "$FAKE_GH_UPDATED" ]]; then
      jq -n --arg sha "$SIGNED_SHA" '{object:{sha:$sha}}'
    else
      jq -n --arg sha "$REMOTE_SHA" '{object:{sha:$sha}}'
    fi
    ;;
  "POST repos/example/consumer/git/trees")
    # Build the tree the way GitHub does: the base tree with each posted blob written over it.
    payload="$(cat)"
    index="$(mktemp)"
    GIT_INDEX_FILE="$index" git read-tree "$(jq -er '.base_tree' <<<"$payload")"
    count="$(jq '.tree | length' <<<"$payload")"
    for ((i = 0; i < count; i++)); do
      entry="$(jq -c ".tree[$i]" <<<"$payload")"
      [[ "$(jq -r '.type' <<<"$entry")" == "blob" ]] || exit 98
      blob="$(jq -j '.content' <<<"$entry" | git hash-object -w --stdin)"
      GIT_INDEX_FILE="$index" git update-index --add \
        --cacheinfo "$(jq -r '.mode' <<<"$entry"),$blob,$(jq -r '.path' <<<"$entry")"
    done
    jq -n --arg sha "$(GIT_INDEX_FILE="$index" git write-tree)" '{sha:$sha}'
    rm -f "$index"
    ;;
  "POST repos/example/consumer/git/commits")
    payload="$(cat)"
    jq -e --arg tree "$EXPECTED_TREE" --arg parent "$EXPECTED_PARENT" \
      '.tree == $tree and .parents == [$parent]' <<<"$payload" >/dev/null || {
      jq -r '.tree' <<<"$payload" >"$FAKE_WRONG_TREE"
      exit 94
    }
    jq -n --arg sha "$SIGNED_SHA" '{sha:$sha,verification:{verified:true,reason:"valid"}}'
    ;;
  "PATCH repos/example/consumer/git/refs/heads/chore/template-sync_deadbee")
    : >"$FAKE_GH_UPDATED"
    jq -n --arg sha "$SIGNED_SHA" '{object:{sha:$sha}}'
    ;;
  "GET repos/example/consumer/commits/$SIGNED_SHA")
    jq -n --arg sha "$SIGNED_SHA" --arg tree "$EXPECTED_TREE" --arg parent "$EXPECTED_PARENT" \
      --arg message "$EXPECTED_MESSAGE" \
      '{sha:$sha,commit:{message:$message,tree:{sha:$tree},verification:{verified:true,reason:"valid"}},parents:[{sha:$parent}]}'
    ;;
  *) exit 96 ;;
esac
FAKE_GH
  chmod +x "$1/gh"
}

workflow() {
  # workflow <file> <sha> <version> [extra step name]
  local file="$1" name
  name="${file##*/}"
  mkdir -p "$(dirname "$file")"
  {
    printf 'name: fixture\non: push\njobs:\n  call:\n'
    printf '    uses: devantler-tech/actions/.github/workflows/%s@%s # %s\n' "$name" "$2" "$3"
    [[ -z "${4:-}" ]] || printf '    # %s\n' "$4"
  } >"$file"
}

# new_case <name>: a fixture repo on its base commit; prints its path.
new_case() {
  local dir="$test_root/$1"
  mkdir -p "$dir/bin" "$dir/repo"
  write_fake_gh "$dir/bin"
  git -C "$dir/repo" init -q -b main
  git -C "$dir/repo" config user.name "Test User"
  git -C "$dir/repo" config user.email "test@example.com"
  git -C "$dir/repo" config commit.gpgsign false
  : >"$dir/compare"
  printf '%s\n' "$dir"
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

# run_case <dir> <expected-tree> → sets rc; stdout/stderr in <dir>/output and <dir>/error.
run_case() {
  local dir="$1"
  export EXPECTED_TREE="$2"
  export EXPECTED_PARENT="$base"
  EXPECTED_MESSAGE="$(git -C "$dir/repo" log -1 --format=%B | sed '${/^$/d;}')"
  export EXPECTED_MESSAGE
  REMOTE_SHA="$(git -C "$dir/repo" rev-parse HEAD)"
  export REMOTE_SHA
  export FAKE_GH_LOG="$dir/gh.log" FAKE_GH_UPDATED="$dir/updated" FAKE_COMPARE="$dir/compare"
  export FAKE_WRONG_TREE="$dir/wrong-tree"
  rc=0
  (
    cd "$dir/repo"
    PATH="$dir/bin:$PATH" GITHUB_REPOSITORY=example/consumer \
      "$helper" --base-sha "$base" --branch-prefix chore/template-sync
  ) >"$dir/output" 2>"$dir/error" || rc=$?
}

# tree_with <dir> <path=file-with-content>... : HEAD's tree with those paths overwritten.
tree_with() {
  local dir="$1" index spec path blob
  shift
  index="$(mktemp)"
  GIT_INDEX_FILE="$index" git -C "$dir/repo" read-tree HEAD
  for spec in "$@"; do
    path="${spec%%=*}"
    blob="$(git -C "$dir/repo" hash-object -w "${spec#*=}")"
    GIT_INDEX_FILE="$index" git -C "$dir/repo" update-index --cacheinfo "100644,$blob,$path"
  done
  GIT_INDEX_FILE="$index" git -C "$dir/repo" write-tree
  rm -f "$index"
}

# ── 1. The wedding-app#332 reproduction: three v13.6.0 pins, template on v13.5.1 ──────────────
dir="$(new_case downgrade)"
r="$dir/repo"
for f in cd release template-sync; do workflow "$r/.github/workflows/$f.yaml" "$v1360" v13.6.0; done
printf 'base readme\n' >"$r/README.md"
commit_all "$r" base
base="$(git -C "$r" rev-parse HEAD)"
for f in cd release template-sync; do cp "$r/.github/workflows/$f.yaml" "$dir/keep-$f.yaml"; done
git -C "$r" switch -q -c chore/template-sync_deadbee
workflow "$r/.github/workflows/cd.yaml" "$v1351" v13.5.1 "a new step from the template"
workflow "$r/.github/workflows/release.yaml" "$v1351" v13.5.1
workflow "$r/.github/workflows/template-sync.yaml" "$v1351" v13.5.1
printf 'synced readme\n' >"$r/README.md"
commit_all "$r" "chore: sync template"
printf '%s...%s behind\n' "$v1360" "$v1351" >"$dir/compare"
# Expected: the template's legitimate edits survive (README, the new comment line in cd.yaml);
# every pin line is the target's v13.6.0 line, byte for byte.
workflow "$dir/expect/cd.yaml" "$v1360" v13.6.0 "a new step from the template"
expected="$(tree_with "$dir" \
  ".github/workflows/cd.yaml=$dir/expect/cd.yaml" \
  ".github/workflows/release.yaml=$dir/keep-release.yaml" \
  ".github/workflows/template-sync.yaml=$dir/keep-template-sync.yaml")"
run_case "$dir" "$expected"
[[ "$rc" -eq 0 ]] || fail "downgrade — the helper failed instead of signing the corrected tree (signed '$(cat "$dir/wrong-tree" 2>/dev/null)'): $(cat "$dir/error")"
grep -qx "$SIGNED_SHA" "$dir/output" || fail "downgrade — no signed sha returned"
[[ "$(grep -c '^::warning' "$dir/output")" -eq 3 ]] ||
  fail "downgrade — expected one ::warning:: per omitted pin: $(cat "$dir/output")"
grep -qx "POST repos/example/consumer/git/trees" "$dir/gh.log" || fail "downgrade — no corrected tree was created"
echo "ok: the wedding-app#332 downgrade is omitted from all three files and the rest of the sync is kept"

# ── 2. A forward upgrade and an unchanged pin are signed exactly as synced ─────────────────────
dir="$(new_case forward)"
r="$dir/repo"
workflow "$r/.github/workflows/cd.yaml" "$v1351" v13.5.1
workflow "$r/.github/workflows/release.yaml" "$v1360" v13.6.0
commit_all "$r" base
base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" switch -q -c chore/template-sync_deadbee
workflow "$r/.github/workflows/cd.yaml" "$v1360" v13.6.0
workflow "$r/.github/workflows/release.yaml" "$v1360" v13.6.0 "an unrelated template edit"
commit_all "$r" "chore: sync template"
printf '%s...%s ahead\n' "$v1351" "$v1360" >"$dir/compare"
run_case "$dir" "$(git -C "$r" rev-parse 'HEAD^{tree}')"
[[ "$rc" -eq 0 ]] || fail "forward — the helper refused a forward upgrade: $(cat "$dir/error")"
! grep -q '^::warning' "$dir/output" || fail "forward — a forward upgrade was reported as omitted"
! grep -q "git/trees" "$dir/gh.log" || fail "forward — the synced tree was rewritten"
[[ "$(grep -c '/compare/' "$dir/gh.log")" -eq 1 ]] ||
  fail "forward — only the changed pin should be ordered: $(cat "$dir/gh.log")"
echo "ok: a forward upgrade and an equal pin are signed exactly as synced"

# ── 3. Diverged history is not forward: the target's pin is kept ───────────────────────────────
dir="$(new_case diverged)"
r="$dir/repo"
workflow "$r/.github/workflows/cd.yaml" "$v1360" v13.6.0
commit_all "$r" base
base="$(git -C "$r" rev-parse HEAD)"
cp "$r/.github/workflows/cd.yaml" "$dir/keep-cd.yaml"
git -C "$r" switch -q -c chore/template-sync_deadbee
workflow "$r/.github/workflows/cd.yaml" "$fork" v13.7.0
printf 'more\n' >"$r/extra.txt"
commit_all "$r" "chore: sync template"
printf '%s...%s diverged\n' "$v1360" "$fork" >"$dir/compare"
run_case "$dir" "$(tree_with "$dir" ".github/workflows/cd.yaml=$dir/keep-cd.yaml")"
[[ "$rc" -eq 0 ]] || fail "diverged — the helper failed instead of keeping the target's pin: $(cat "$dir/error")"
grep -q '^::warning' "$dir/output" || fail "diverged — the omitted pin was not reported"
echo "ok: a pin whose history diverged from the target's is not treated as an upgrade"

# ── 4. An ordering the API cannot answer fails closed, before anything is signed ───────────────
dir="$(new_case unordered)"
r="$dir/repo"
workflow "$r/.github/workflows/cd.yaml" "$v1360" v13.6.0
commit_all "$r" base
base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" switch -q -c chore/template-sync_deadbee
workflow "$r/.github/workflows/cd.yaml" "$v1351" v13.5.1
commit_all "$r" "chore: sync template"
run_case "$dir" "$(git -C "$r" rev-parse 'HEAD^{tree}')"
[[ "$rc" -ne 0 ]] || fail "unordered — the helper signed a pin change it could not order"
[[ ! -f "$dir/updated" ]] || fail "unordered — the branch was moved"
! grep -q "git/commits" "$dir/gh.log" || fail "unordered — a commit was created"
grep -q "could not order" "$dir/error" || fail "unordered — the refusal does not name the ordering: $(cat "$dir/error")"
echo "ok: a pin the compare API cannot order is refused before signing"

# ── 5. A regressive line the template also moved cannot be restored safely: fail closed ────────
dir="$(new_case moved)"
r="$dir/repo"
workflow "$r/.github/workflows/cd.yaml" "$v1360" v13.6.0
commit_all "$r" base
base="$(git -C "$r" rev-parse HEAD)"
git -C "$r" switch -q -c chore/template-sync_deadbee
sed "s|^    uses: devantler-tech/actions/.github/workflows/cd.yaml@$v1360 # v13.6.0|      uses: devantler-tech/actions/.github/workflows/cd.yaml@$v1351 # v13.5.1|" \
  "$r/.github/workflows/cd.yaml" >"$dir/moved.yaml"
mv "$dir/moved.yaml" "$r/.github/workflows/cd.yaml"
commit_all "$r" "chore: sync template"
printf '%s...%s behind\n' "$v1360" "$v1351" >"$dir/compare"
run_case "$dir" "$(git -C "$r" rev-parse 'HEAD^{tree}')"
[[ "$rc" -ne 0 ]] || fail "moved — the helper signed a downgrade it could not restore"
[[ ! -f "$dir/updated" ]] || fail "moved — the branch was moved"
grep -q "cannot restore" "$dir/error" || fail "moved — the refusal does not explain itself: $(cat "$dir/error")"
echo "ok: a downgrade on a line the template also reshaped is refused rather than guessed at"

echo "PASS: template sync keeps every devantler-tech/actions pin at or ahead of the target's"
