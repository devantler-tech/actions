#!/usr/bin/env bash
set -euo pipefail

ci_workflow="${1:-.github/workflows/ci.yaml}"
approve_action="${2:-approve-pr/action.yaml}"
status=0

fail() {
  echo "::error::$*"
  status=1
}

job_permissions="$(
  yq -o=json -I=0 '.jobs."test-approve-pr".permissions // {}' "$ci_workflow" |
    jq -cS .
)"
[[ "$job_permissions" == '{"contents":"read"}' ]] ||
  fail "test-approve-pr must run with contents: read only; got $job_permissions"

job_definition="$(yq -o=json -I=0 '.jobs."test-approve-pr"' "$ci_workflow")"
[[ "$job_definition" != *'secrets.'* &&
  "$job_definition" != *'APP_PRIVATE_KEY'* &&
  "$job_definition" != *'APP_CLIENT_ID'* ]] ||
  fail "test-approve-pr must not expose GitHub App credentials through any job field"

job_condition="$(yq -r '.jobs."test-approve-pr".if // ""' "$ci_workflow")"
[[ "$job_condition" != *"pull_request.user.login"* ]] ||
  fail "test-approve-pr must not author-gate a privileged pull_request path; it should be credential-free for every event"

checkout_persistence="$(
  yq -r '
    .jobs."test-approve-pr".steps[]
    | select(.uses | test("^actions/checkout@"))
    | .with."persist-credentials"
  ' "$ci_workflow"
)"
[[ "$checkout_persistence" == "false" ]] ||
  fail "test-approve-pr checkout must keep persist-credentials false; got $checkout_persistence"

approve_inputs="$(
  yq -o=json -I=0 '
    .jobs."test-approve-pr".steps[]
    | select(.uses == "./approve-pr")
    | .with
  ' "$ci_workflow"
)"
approve_input_keys="$(jq -r 'keys | sort | join(",")' <<<"$approve_inputs")"
[[ "$approve_input_keys" == "dry-run,pr-number" ]] ||
  fail "test-approve-pr must pass only dry-run and pr-number; got keys: $approve_input_keys"
[[ "$(jq -r '."dry-run"' <<<"$approve_inputs")" == "true" ]] ||
  fail "test-approve-pr must exercise approve-pr with dry-run=true"

private_key_required="$(yq -r '.inputs."app-private-key".required // false' "$approve_action")"
[[ "$private_key_required" == "false" ]] ||
  fail "approve-pr app-private-key must be optional at metadata validation so dry-run callers need no secret"

token_guard="$(yq -r '.runs.steps[] | select(.id == "app-token") | .if // ""' "$approve_action")"
approve_guard="$(yq -r '.runs.steps[] | select(.name == "✅ Approve pull request") | .if // ""' "$approve_action")"
[[ "$token_guard" == "inputs.dry-run != 'true'" ]] ||
  fail "App-token mint must stay disabled in dry-run mode; got: $token_guard"
[[ "$approve_guard" == "inputs.dry-run != 'true'" ]] ||
  fail "approval mutation must stay disabled in dry-run mode; got: $approve_guard"

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "PASS: approve-pr CI exercises the real local action without write permissions or App credentials"
