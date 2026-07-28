#!/usr/bin/env bash

set -euo pipefail

selector="${1:-.scripts/find-trusted-superseding-pr-run.sh}"
fixtures="${2:-.github/tests/superseding-pr-runs.json}"
trusted_actors='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","devantler"]'
status=0

while IFS= read -r fixture; do
  name="$(jq -r .name <<<"$fixture")"
  current_run_id="$(jq -r .current_run_id <<<"$fixture")"
  workflow_id="$(jq -r .workflow_id <<<"$fixture")"
  pr_number="$(jq -r .pr_number <<<"$fixture")"
  expected_actor="$(jq -r .expected_actor <<<"$fixture")"
  runs="$(jq -c .runs <<<"$fixture")"

  set +e
  actual_actor="$(
    bash "$selector" "$current_run_id" "$workflow_id" "$pr_number" "$trusted_actors" \
      <<<"$runs"
  )"
  selector_exit=$?
  set -e

  if [[ -n "$expected_actor" ]]; then
    if [[ "$selector_exit" -ne 0 || "$actual_actor" != "$expected_actor" ]]; then
      echo "::error file=$fixtures::fixture '$name' expected trusted actor '$expected_actor', got exit=$selector_exit actor='$actual_actor'"
      status=1
    fi
  elif [[ "$selector_exit" -eq 0 || -n "$actual_actor" ]]; then
    echo "::error file=$fixtures::fixture '$name' expected no trusted superseding run, got exit=$selector_exit actor='$actual_actor'"
    status=1
  fi
done < <(jq -c '.[]' "$fixtures")

exit "$status"
