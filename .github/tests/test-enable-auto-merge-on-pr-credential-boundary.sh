#!/usr/bin/env bash
set -euo pipefail

ci_workflow="${1:-.github/workflows/ci.yaml}"
action_file="${2:-enable-auto-merge-on-pr/action.yaml}"
status=0

fail() {
  echo "::error::$*"
  status=1
}

job_permissions="$(
  yq -o=json -I=0 '.jobs."test-enable-auto-merge-on-pr".permissions // {}' "$ci_workflow" |
    jq -cS .
)"
[[ "$job_permissions" == '{"contents":"read"}' ]] ||
  fail "test-enable-auto-merge-on-pr must run with contents: read only; got $job_permissions"

checkout_persistence="$(
  yq -r '
    .jobs."test-enable-auto-merge-on-pr".steps[]
    | select(.uses | test("^actions/checkout@"))
    | .with."persist-credentials"
  ' "$ci_workflow"
)"
[[ "$checkout_persistence" == "false" ]] ||
  fail "test-enable-auto-merge-on-pr checkout must keep persist-credentials false; got $checkout_persistence"

action_inputs="$(
  yq -o=json -I=0 '
    .jobs."test-enable-auto-merge-on-pr".steps[]
    | select(.uses == "./enable-auto-merge-on-pr")
    | .with
  ' "$ci_workflow"
)"
action_input_keys="$(jq -r 'keys | sort | join(",")' <<<"$action_inputs")"
[[ "$action_input_keys" == "dry-run,pr-number" ]] ||
  fail "test-enable-auto-merge-on-pr must exercise the checked-out action with only dry-run and pr-number; got keys: $action_input_keys"
[[ "$(jq -r '."dry-run"' <<<"$action_inputs")" == "true" ]] ||
  fail "test-enable-auto-merge-on-pr must keep dry-run=true"

mutation_guard="$(
  yq -r '
    .runs.steps[]
    | select(.name == "🤖 Enable auto-merge")
    | .if // ""
  ' "$action_file"
)"
[[ "$mutation_guard" == *"inputs.dry-run != 'true'"* ]] ||
  fail "enable-auto-merge-on-pr mutation must remain disabled in dry-run mode; got: $mutation_guard"

if [[ "$status" -ne 0 ]]; then
  exit "$status"
fi

echo "PASS: enable-auto-merge-on-pr CI exercises the checked-out action without write permissions"
