#!/usr/bin/env bash

set -euo pipefail

wrapper="${1:-.scripts/disarm-untrusted-event.sh}"
mock_bin="${2:-.github/tests/disarm-auto-merge-mock-bin}"
mock_log="$(mktemp)"
trap 'rm -f "$mock_log"' EXIT

trusted_actors='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","devantler"]'
live_pr='{"headRefOid":"new-head","updatedAt":"2026-07-28T20:00:02Z"}'
trusted_same_workflow='{"workflow_runs":[{"id":110,"workflow_id":7,"actor":{"login":"devantler"},"pull_requests":[{"number":42}]}]}'
trusted_other_workflow='{"workflow_runs":[{"id":110,"workflow_id":8,"actor":{"login":"devantler"},"pull_requests":[{"number":42}]}]}'

metadata_failure_output="$(
  MOCK_GH_LOG="$mock_log" \
    MOCK_GH_STATE="PR_node_id true false" \
    MOCK_PR_VIEW_JSON="$live_pr" \
    MOCK_WORKFLOW_LOOKUP_FAIL=true \
    PATH="$mock_bin:$PATH" \
    bash "$wrapper" devantler-tech/actions 42 100 old-head \
      2026-07-28T20:00:01Z "$trusted_actors"
)"
if ! grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log" ||
  [[ "$metadata_failure_output" != *"workflow identity lookup failed"* ]]; then
  echo "::error file=$wrapper::workflow metadata failure must revoke existing auto-merge"
  exit 1
fi

: >"$mock_log"
list_failure_output="$(
  MOCK_GH_LOG="$mock_log" \
    MOCK_GH_STATE="PR_node_id true false" \
    MOCK_PR_VIEW_JSON="$live_pr" \
    MOCK_WORKFLOW_ID=7 \
    MOCK_RUN_LIST_FAIL=true \
    PATH="$mock_bin:$PATH" \
    bash "$wrapper" devantler-tech/actions 42 100 old-head \
      2026-07-28T20:00:01Z "$trusted_actors"
)"
if ! grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log" ||
  [[ "$list_failure_output" != *"workflow run lookup failed"* ]]; then
  echo "::error file=$wrapper::workflow run-list failure must revoke existing auto-merge"
  exit 1
fi

: >"$mock_log"
trusted_output="$(
  MOCK_GH_LOG="$mock_log" \
    MOCK_GH_STATE="PR_node_id true false" \
    MOCK_PR_VIEW_JSON="$live_pr" \
    MOCK_WORKFLOW_ID=7 \
    MOCK_RUN_PAGE="$trusted_same_workflow" \
    PATH="$mock_bin:$PATH" \
    bash "$wrapper" devantler-tech/actions 42 100 old-head \
      2026-07-28T20:00:01Z "$trusted_actors"
)"
if grep -Fq $'pr\tmerge\t42\t--disable-auto' "$mock_log" ||
  grep -Fq "autoMergeRequest" "$mock_log" ||
  [[ "$trusted_output" != *"newer trusted pull_request run from devantler"* ]]; then
  echo "::error file=$wrapper::a proven newer trusted run of the same workflow must be the only non-revocation path"
  exit 1
fi

: >"$mock_log"
other_workflow_output="$(
  MOCK_GH_LOG="$mock_log" \
    MOCK_GH_STATE="PR_node_id true false" \
    MOCK_PR_VIEW_JSON="$live_pr" \
    MOCK_WORKFLOW_ID=7 \
    MOCK_RUN_PAGE="$trusted_other_workflow" \
    PATH="$mock_bin:$PATH" \
    bash "$wrapper" devantler-tech/actions 42 100 old-head \
      2026-07-28T20:00:01Z "$trusted_actors"
)"
if ! grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log" ||
  [[ "$other_workflow_output" != *"no trusted same-workflow reauthorization was proven"* ]]; then
  echo "::error file=$wrapper::trusted activity in another workflow must still revoke fail-closed"
  exit 1
fi

echo "stale rejected-event wrapper revokes on lookup failures and skips only proven same-workflow reauthorization"
