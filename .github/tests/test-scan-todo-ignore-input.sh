#!/usr/bin/env bash

# Guards the reusable TODO workflow's optional ignore contract. The dry-run caller in ci.yaml
# proves the input is accepted by GitHub's workflow schema; these assertions prove the value is
# also forwarded to the shared scanner action when the real job runs.

set -euo pipefail

workflow=".github/workflows/scan-for-todo-comments.yaml"
action="create-issues-from-todos/action.yaml"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "missing workflow: $workflow"
[[ -f "$action" ]] || fail "missing action: $action"

input_type="$(yq -r '.on.workflow_call.inputs.ignore.type // ""' "$workflow")"
[[ "$input_type" == "string" ]] ||
  fail "ignore must be a string workflow_call input; got: ${input_type:-<missing>}"

input_required="$(yq -r '.on.workflow_call.inputs.ignore.required // false' "$workflow")"
[[ "$input_required" == "false" ]] ||
  fail "ignore must remain optional; got required: $input_required"

input_default="$(yq -r '.on.workflow_call.inputs.ignore.default // ""' "$workflow")"
[[ -z "$input_default" ]] ||
  fail "ignore must default to an empty pattern; got: $input_default"

forwarded="$(yq -r \
  '.jobs.todos.steps[]
   | select(.uses == "./.devantler-tech-actions/create-issues-from-todos")
   | .with.ignore // ""' "$workflow")"
# shellcheck disable=SC2016 # GitHub expression compared literally.
[[ "$forwarded" == '${{ inputs.ignore }}' ]] ||
  fail "ignore must be forwarded unchanged to create-issues-from-todos; got: ${forwarded:-<missing>}"

default_has_ignore="$(yq -r \
  '.jobs["test-scan-for-todo-comments"].with | has("ignore")' .github/workflows/ci.yaml)"
[[ "$default_has_ignore" == "false" ]] ||
  fail "the default-state workflow_call test must omit ignore"

opt_in_uses="$(yq -r \
  '.jobs["test-scan-for-todo-comments-ignore"].uses // ""' .github/workflows/ci.yaml)"
[[ "$opt_in_uses" == "./.github/workflows/scan-for-todo-comments.yaml" ]] ||
  fail "the opt-in workflow_call test must invoke scan-for-todo-comments.yaml"

ci_pattern="$(yq -r '.jobs["test-scan-for-todo-comments-ignore"].with.ignore // ""' \
  .github/workflows/ci.yaml)"
[[ ".github/tests/fixture" =~ $ci_pattern ]] ||
  fail "the CI ignore pattern must match the intended .github/tests fixture path"
[[ ! "xgithub/tests/fixture" =~ $ci_pattern ]] ||
  fail "the CI ignore pattern must not treat the leading dot as a regex wildcard"

action_required="$(yq -r '.inputs.ignore.required // false' "$action")"
[[ "$action_required" == "false" ]] ||
  fail "the scanner action's ignore input must remain optional; got required: $action_required"

action_default="$(yq -r '.inputs.ignore.default // ""' "$action")"
[[ -z "$action_default" ]] ||
  fail "the scanner action's ignore input must default to empty; got: $action_default"

action_env="$(yq -r \
  '.runs.steps[]
   | select(.name == "📝 Create issues from TODOs")
   | .env.INPUT_IGNORE // ""' "$action")"
# shellcheck disable=SC2016 # GitHub expression compared literally.
[[ "$action_env" == '${{ inputs.ignore }}' ]] ||
  fail "the scanner action must bind INPUT_IGNORE to inputs.ignore; got: ${action_env:-<missing>}"

action_run="$(yq -r \
  '.runs.steps[]
   | select(.name == "📝 Create issues from TODOs")
   | .run' "$action")"
grep -q -- '--env INPUT_IGNORE' <<<"$action_run" ||
  fail "the scanner container invocation must pass INPUT_IGNORE"

echo "scan-for-todo ignore input contract enforced ✅"
