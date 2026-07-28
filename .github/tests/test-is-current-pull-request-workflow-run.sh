#!/usr/bin/env bash

set -euo pipefail

selector="${1:-.scripts/is-current-pull-request-workflow-run.sh}"
fixtures="${2:-.github/tests/current-pull-request-runs.json}"
status=0

while IFS= read -r fixture; do
  name="$(jq -r .name <<<"$fixture")"
  current_run_id="$(jq -r .current_run_id <<<"$fixture")"
  workflow_id="$(jq -r .workflow_id <<<"$fixture")"
  pr_number="$(jq -r .pr_number <<<"$fixture")"
  expected_exit="$(jq -r .expected_exit <<<"$fixture")"
  runs="$(jq -c .runs <<<"$fixture")"

  set +e
  selector_output="$(
    bash "$selector" "$current_run_id" "$workflow_id" "$pr_number" <<<"$runs" 2>&1
  )"
  selector_exit=$?
  set -e

  if [[ "$selector_exit" -ne "$expected_exit" ]]; then
    echo "::error file=$fixtures::fixture '$name' expected exit=$expected_exit, got $selector_exit: $selector_output"
    status=1
  fi
done < <(jq -c '.[]' "$fixtures")

exit "$status"
