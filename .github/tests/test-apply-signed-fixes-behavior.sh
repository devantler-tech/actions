#!/usr/bin/env bash
# Execute the workflow's real Bash bodies; only the GitHub API is simulated.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${1:-$repo_root/.github/workflows/apply-signed-fixes.yaml}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
export REAL_GIT REAL_BASE64
REAL_GIT="$(command -v git)"
REAL_BASE64="$(command -v base64)"
count=0
fail() { echo "FAIL: ${case_name:-setup}: $*" >&2; exit 1; }

extract() {
  local name="$1" target="$2" result
  result="$(STEP_NAME="$name" yq -o=json '[.jobs."apply-fixes".steps[] | select(.name == strenv(STEP_NAME)) | .run]' "$workflow")" || fail 'cannot read workflow'
  jq -e 'length == 1 and (.[0] | type == "string" and length > 0)' <<< "$result" >/dev/null || fail "missing or ambiguous step: $name"
  jq -r '.[0]' <<< "$result" > "$test_root/$target.sh"
}
extract '🔏 Verify an applied-fixes head is signed' tip
extract 'Apply fixes' apply
extract '📤 Commit the applied fixes' commit

new_case() {
  case_name="$1"
  export CASE_ROOT="$test_root/$case_name"
  mkdir -p "$CASE_ROOT/repo" "$CASE_ROOT/bin" "$CASE_ROOT/runtime"
  export REPO=example/consumer BRANCH=codex/fixes COMMIT_MESSAGE='chore: apply fixes'
  export API_MODE=success READ_FAILURE=none GIT_FAILURE=none
  export CREATED_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export GH_TOKEN=offline-fixture-only RUNNER_TEMP="$CASE_ROOT/runtime" ARTIFACT_NAME=fixes
  "$REAL_GIT" -C "$CASE_ROOT/repo" init -q -b "$BRANCH"
  "$REAL_GIT" -C "$CASE_ROOT/repo" config user.name 'Fixture Author'
  "$REAL_GIT" -C "$CASE_ROOT/repo" config user.email fixture@example.invalid
  "$REAL_GIT" -C "$CASE_ROOT/repo" config commit.gpgsign false
  "$REAL_GIT" -C "$CASE_ROOT/repo" config core.fileMode true
  printf 'before\n' > "$CASE_ROOT/repo/file.txt"
  printf 'delete me\n' > "$CASE_ROOT/repo/delete.txt"
  printf '#!/bin/sh\nexit 0\n' > "$CASE_ROOT/repo/existing.sh"
  chmod +x "$CASE_ROOT/repo/existing.sh"
  "$REAL_GIT" -C "$CASE_ROOT/repo" add -- file.txt delete.txt existing.sh
  "$REAL_GIT" -C "$CASE_ROOT/repo" commit -qm "${2:-ordinary contribution}"
  export BASE_SHA HEAD_SHA
  BASE_SHA="$("$REAL_GIT" -C "$CASE_ROOT/repo" rev-parse HEAD)"
  HEAD_SHA="$BASE_SHA"
  printf '%s\n' "$BASE_SHA" > "$CASE_ROOT/remote-head"
  : > "$CASE_ROOT/api.log"
  jq -n --arg message "$COMMIT_MESSAGE" '{commit:{message:$message,verification:{verified:true}}}' > "$CASE_ROOT/head.json"
  printf '{"commit":{"verification":{"verified":true}}}\n' > "$CASE_ROOT/verification.json"
  cp "$repo_root/.github/tests/applied-fixes/fake-gh.sh" "$CASE_ROOT/bin/gh"
  cat > "$CASE_ROOT/bin/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "$GIT_FAILURE" ]]; then echo 'fixture Git read failed' >&2; exit 89; fi
case "${1:-}" in
  commit|push) echo 'unexpected Git write' >&2; exit 88 ;;
esac
exec "$REAL_GIT" "$@"
GIT
  # Production runs on Linux. macOS base64 lacks -w0; line wrapping is already
  # normalized by the production jq expression, so remove only that formatting flag.
  cat > "$CASE_ROOT/bin/base64" <<'BASE64'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == -w0 ]]; then shift; fi
exec "$REAL_BASE64" "$@"
BASE64
  chmod +x "$CASE_ROOT/bin/gh" "$CASE_ROOT/bin/git" "$CASE_ROOT/bin/base64"
}

run_step() {
  local step="$1" expected="$2" diagnostic="${3:-}" status=0
  (cd "$CASE_ROOT/repo"; PATH="$CASE_ROOT/bin:$PATH" bash "$test_root/$step.sh") > "$CASE_ROOT/output" 2>&1 || status=$?
  if [[ "$expected" == success ]]; then
    [[ $status == 0 ]] || { cat "$CASE_ROOT/output" >&2; fail "$step unexpectedly failed ($status)"; }
  else
    [[ $status != 0 ]] || fail "$step accepted a failing fixture"
  fi
  if [[ -n "$diagnostic" ]]; then grep -Fq -- "$diagnostic" "$CASE_ROOT/output" || { cat "$CASE_ROOT/output" >&2; fail "missing diagnostic: $diagnostic"; }; fi
  count=$((count + 1))
  echo "PASS: $case_name ($step)"
}
calls() { awk -v endpoint="$1" '$0 == endpoint {n++} END {print n+0}' "$CASE_ROOT/api.log"; }
unchanged() { [[ "$(cat "$CASE_ROOT/remote-head")" == "$BASE_SHA" ]] || fail 'unexpected remote write'; }
no_api() { [[ ! -s "$CASE_ROOT/api.log" ]] || fail 'unexpected API call'; }
changed() { printf 'after\n' > "$CASE_ROOT/repo/file.txt"; }
verification() {
  jq -n --argjson verified "$1" '{commit:{verification:{verified:$verified}}}' > "$CASE_ROOT/verification.json"
  jq -n --arg message "$COMMIT_MESSAGE" --argjson verified "$1" '{commit:{message:$message,verification:{verified:$verified}}}' > "$CASE_ROOT/head.json"
}

new_case signed-tip
run_step tip success 'Verified signature'
[[ "$(calls "repos/$REPO/commits/$HEAD_SHA")" == 1 ]] || fail 'tip identity or read count changed'
unchanged

new_case unrelated-tip
printf '{"commit":{"message":"ordinary contribution","verification":{"verified":false}}}\n' > "$CASE_ROOT/head.json"
run_step tip success 'nothing to verify'
unchanged

for value in false null; do
  new_case "tip-$value"; verification "$value"
  run_step tip failure 'not signed'; unchanged
done
for response in empty malformed missing-message; do
  new_case "tip-$response"
  case "$response" in
    empty) : > "$CASE_ROOT/head.json" ;;
    malformed) printf 'not JSON\n' > "$CASE_ROOT/head.json" ;;
    missing-message) printf '{"commit":{}}\n' > "$CASE_ROOT/head.json" ;;
  esac
  run_step tip failure; unchanged
done
new_case tip-read-failed
READ_FAILURE='head'
run_step tip failure 'Could not read head commit'; unchanged

new_case no-change
run_step commit success 'No applied fixes left to commit'; no_api; unchanged
for value in true false null; do
  new_case "replacement-$value" 'chore: apply fixes'; verification "$value"
  if [[ "$value" == true ]]; then run_step commit success 'Verified signature'; else run_step commit failure 'not signed'; fi
  [[ "$(calls "repos/$REPO/commits/$HEAD_SHA")" == 1 && "$(calls graphql)" == 0 ]] || fail 'replacement must verify without publishing'
  unchanged
done
for mode in empty malformed failed; do
  new_case "replacement-$mode" 'chore: apply fixes'
  case "$mode" in
    empty) : > "$CASE_ROOT/verification.json" ;;
    malformed) printf 'not JSON\n' > "$CASE_ROOT/verification.json" ;;
    failed) READ_FAILURE=verification ;;
  esac
  run_step commit failure; unchanged
done

new_case payload-integrity
changed
rm "$CASE_ROOT/repo/delete.txt"
printf '#!/bin/sh\nexit 1\n' > "$CASE_ROOT/repo/existing.sh"
odd=$'line\nbreak.txt'
for name in ':odd.txt' 'with space.txt' '[x]*.txt' "$odd"; do printf '%s\n' "$name" > "$CASE_ROOT/repo/$name"; done
dd if=/dev/zero of="$CASE_ROOT/repo/large.bin" bs=1024 count=256 2>/dev/null
"$REAL_GIT" -C "$CASE_ROOT/repo" add -- file.txt delete.txt existing.sh
run_step commit success
[[ "$(calls graphql)" == 1 && "$(calls "repos/$REPO/commits/$CREATED_SHA")" == 1 ]] || fail 'creation or verification identity/count changed'
[[ "$(cat "$CASE_ROOT/remote-head")" == "$CREATED_SHA" ]] || fail 'successful API response did not model the write'
jq -e '.variables.input.fileChanges | (.additions | length) == 7 and .deletions == [{path:"delete.txt"}]' "$CASE_ROOT/request.json" >/dev/null || fail 'wrong payload file set'
for name in file.txt existing.sh large.bin ':odd.txt' 'with space.txt' '[x]*.txt' "$odd"; do
  jq -r --arg name "$name" '.variables.input.fileChanges.additions[] | select(.path == $name) | .contents' "$CASE_ROOT/request.json" | "$REAL_BASE64" -d > "$CASE_ROOT/decoded"
  cmp "$CASE_ROOT/repo/$name" "$CASE_ROOT/decoded" || fail "payload bytes changed: $name"
done
jq -e '[.variables.input.fileChanges.additions[].path | select(startswith(".devantler-tech-actions") or contains("fake-gh") or contains("commit.sh"))] | length == 0' "$CASE_ROOT/request.json" >/dev/null || fail 'test helper leaked into consumer payload'
[[ "$("$REAL_GIT" -C "$CASE_ROOT/repo" rev-parse HEAD)" == "$BASE_SHA" ]] || fail 'workflow made a local commit'

for value in false null; do
  new_case "created-$value"; changed; verification "$value"
  run_step commit failure 'not signed'
  [[ "$(calls graphql)" == 1 && "$(cat "$CASE_ROOT/remote-head")" == "$CREATED_SHA" ]] || fail 'verification must follow one atomic write'
done
for mode in empty malformed failed; do
  new_case "created-verification-$mode"; changed
  case "$mode" in
    empty) : > "$CASE_ROOT/verification.json" ;;
    malformed) printf 'not JSON\n' > "$CASE_ROOT/verification.json" ;;
    failed) READ_FAILURE=verification ;;
  esac
  run_step commit failure
  [[ "$(calls graphql)" == 1 ]] || fail 'uncertain verification retried the mutation'
done
for mode in stale rejected errors empty malformed missing-oid; do
  new_case "mutation-$mode"; changed; API_MODE="$mode"
  run_step commit failure
  [[ "$(calls graphql)" == 1 && "$(wc -l < "$CASE_ROOT/api.log" | tr -d ' ')" == 1 ]] || fail 'failed mutation was retried or verified as successful'
  case "$mode" in stale|rejected|errors) unchanged ;; esac
done
for operation in status log rev-parse; do
  new_case "git-$operation-failed"
  if [[ "$operation" == rev-parse ]]; then changed; fi
  GIT_FAILURE="$operation"
  run_step commit failure 'fixture Git read failed'; no_api; unchanged
done
for mode in new-executable changed-mode symlink; do
  new_case "unsupported-$mode"
  case "$mode" in
    new-executable) printf 'exit 0\n' > "$CASE_ROOT/repo/new.sh"; chmod +x "$CASE_ROOT/repo/new.sh" ;;
    changed-mode) chmod +x "$CASE_ROOT/repo/file.txt" ;;
    symlink) ln -s file.txt "$CASE_ROOT/repo/link.txt" ;;
  esac
  run_step commit failure '::error'; no_api; unchanged
done

new_case patch-and-replacement
changed
"$REAL_GIT" -C "$CASE_ROOT/repo" diff --binary --full-index HEAD > "$RUNNER_TEMP/$ARTIFACT_NAME.patch"
"$REAL_GIT" -C "$CASE_ROOT/repo" restore -- file.txt
run_step apply success
"$REAL_GIT" -C "$CASE_ROOT/repo" diff --cached --exit-code --quiet && fail 'patch was not staged'
run_step apply success 'already applied'
no_api; unchanged

new_case patch-conflict
changed
"$REAL_GIT" -C "$CASE_ROOT/repo" diff --binary --full-index HEAD > "$RUNNER_TEMP/$ARTIFACT_NAME.patch"
printf 'conflicting edit\n' > "$CASE_ROOT/repo/file.txt"
run_step apply failure; no_api; unchanged

echo "PASS: applied-fixes behavior ($count scenarios); API simulation made no network calls"
