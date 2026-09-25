#!/usr/bin/env bash
# Deliberate regressions are checked independently of the signer's digest guards.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="$repo_root/.github/workflows/apply-signed-fixes.yaml"
suite="$repo_root/.github/tests/test-apply-signed-fixes-behavior.sh"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
yq -o=json '.' "$workflow" > "$temporary/source.json"
count=0
mutate() {
  local label="$1" step="$2" before="$3" after="$4" diagnostic="$5"
  jq -e --arg step "$step" --arg before "$before" '
    [.jobs."apply-fixes".steps[] | select(.name == $step) | .run | split($before) | length] == [2]
  ' "$temporary/source.json" >/dev/null || { echo "FAIL: mutation anchor drifted: $label" >&2; exit 1; }
  jq --arg step "$step" --arg before "$before" --arg after "$after" '
    (.jobs."apply-fixes".steps[] | select(.name == $step) | .run) |= (split($before) | join($after))
  ' "$temporary/source.json" > "$temporary/mutated.yaml"
  if bash "$suite" "$temporary/mutated.yaml" > "$temporary/output" 2>&1; then
    echo "FAIL: behavioral suite accepted $label" >&2; exit 1
  fi
  grep -Fq -- "$diagnostic" "$temporary/output" || {
    cat "$temporary/output" >&2; echo "FAIL: $label failed for the wrong reason" >&2; exit 1
  }
  count=$((count + 1))
  echo "PASS: behavioral suite rejects $label"
}

tip='🔏 Verify an applied-fixes head is signed'
commit='📤 Commit the applied fixes'
# Match literal production text; never evaluate replacement strings as code.
# shellcheck disable=SC2016
mutate 'unsigned event head' "$tip" 'if [ "$verified" != "true" ]; then' 'if false; then' 'tip-false: tip accepted a failing fixture'
# shellcheck disable=SC2016
mutate 'unsigned replacement head' "$commit" 'if [ "$verified" != "true" ]; then' 'if false; then' 'replacement-false: commit accepted a failing fixture'
# shellcheck disable=SC2016
mutate 'missing post-publication verification' "$commit" 'verify_signed "$oid"' ':' 'payload-integrity: creation or verification identity/count changed'
# shellcheck disable=SC2016
mutate 'wrong expected head' "$commit" 'expectedHeadOid: $oid,' 'expectedHeadOid: "0000000000000000000000000000000000000000",' 'payload-integrity: commit unexpectedly failed'
# shellcheck disable=SC2016
mutate 'ignored Git status failure' "$commit" 'git status --porcelain -z --no-renames -uall >"$workdir/status"' 'git status --porcelain -z --no-renames -uall >"$workdir/status" || true' 'git-status-failed: commit accepted a failing fixture'
# shellcheck disable=SC2016
mutate 'ignored Git headline failure' "$commit" 'headline="$(git log -1 --format=%s)"' 'headline="$(git log -1 --format=%s)" || true' 'git-log-failed: commit accepted a failing fixture'
# shellcheck disable=SC2016
mutate 'ignored Git head failure' "$commit" 'head_oid="$(git rev-parse HEAD)"' 'head_oid="$(git rev-parse HEAD)" || true' 'git-rev-parse-failed: unexpected API call'

before=$(cat <<'BLOCK'
if ! jq -e 'type == "object" and (.commit | type == "object") and (.commit.message | type == "string")' <<<"$head_json" >/dev/null; then
  echo "::error::Head commit ${HEAD_SHA} returned no valid commit message."
  exit 1
fi
BLOCK
)
mutate 'empty head response accepted as unrelated' "$tip" "$before" ':' 'tip-empty: tip accepted a failing fixture'
echo "PASS: all $count behavioral mutations were rejected for their intended reason"
