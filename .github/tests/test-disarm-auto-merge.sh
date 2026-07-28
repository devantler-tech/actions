#!/usr/bin/env bash

set -euo pipefail

script="${1:-.scripts/disarm-auto-merge.sh}"
mock_bin="${2:-.github/tests/disarm-auto-merge-mock-bin}"
mock_log="$(mktemp)"
trap 'rm -f "$mock_log"' EXIT

armed_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id true true" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42
)"

if ! grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log"; then
  echo "::error file=$script::classic auto-merge state was not disabled"
  exit 1
fi
if ! grep -Fq "dequeuePullRequest" "$mock_log" ||
  ! grep -Fq -- $'-f\tid=PR_node_id' "$mock_log"; then
  echo "::error file=$script::merge-queue state was not dequeued with the pull request node ID"
  exit 1
fi
if [[ "$armed_output" != *"Auto-merge DISARMED"* ||
  "$armed_output" != *"DEQUEUED from the merge queue"* ]]; then
  echo "::error file=$script::revocation must report both state changes"
  exit 1
fi

: >"$mock_log"
no_op_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id false false" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42
)"

if [[ "$(wc -l <"$mock_log" | tr -d '[:space:]')" != "1" ||
  "$no_op_output" != *"no pending auto-merge or merge-queue entry"* ]]; then
  echo "::error file=$script::the no-op state must perform only its read-only state query"
  exit 1
fi

echo "disarm script revokes classic and merge-queue state and preserves the no-op path"
