#!/usr/bin/env bash

set -euo pipefail

script="${1:-.scripts/disarm-auto-merge.sh}"
mock_bin="${2:-.github/tests/disarm-auto-merge-mock-bin}"
mock_log="$(mktemp)"
trap 'rm -f "$mock_log"' EXIT

armed_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id true false 2026-07-28T19:00:00Z null" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42
)"

if ! grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log" ||
  grep -Fq "dequeuePullRequest" "$mock_log" ||
  [[ "$armed_output" != *"Auto-merge DISARMED"* ||
    "$armed_output" == *"DEQUEUED from the merge queue"* ]]; then
  echo "::error file=$script::classic auto-merge state was not disabled"
  exit 1
fi

: >"$mock_log"
queued_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id false true null 2026-07-28T19:00:00Z" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42
)"

if ! grep -Fq "dequeuePullRequest" "$mock_log" ||
  ! grep -Fq -- $'-f\tid=PR_node_id' "$mock_log" ||
  grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log" ||
  [[ "$queued_output" != *"DEQUEUED from the merge queue"* ||
    "$queued_output" == *"Auto-merge DISARMED"* ]]; then
  echo "::error file=$script::merge-queue state was not dequeued with the pull request node ID"
  exit 1
fi

: >"$mock_log"
no_op_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id false false null null" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42
)"

if [[ "$(wc -l <"$mock_log" | tr -d '[:space:]')" != "1" ||
  "$no_op_output" != *"no pending auto-merge or merge-queue entry"* ]]; then
  echo "::error file=$script::the no-op state must perform only its read-only state query"
  exit 1
fi

: >"$mock_log"
newer_arming_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id true false 2026-07-28T20:00:01Z null" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42 2026-07-28T20:00:00Z
)"
if [[ "$(wc -l <"$mock_log" | tr -d '[:space:]')" != "1" ||
  "$newer_arming_output" != *"newer authorization"* ]]; then
  echo "::error file=$script::a newer serialized classic auto-merge authorization must not be revoked by a stale rejected event"
  exit 1
fi

: >"$mock_log"
newer_queue_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id false true null 2026-07-28T20:00:01Z" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42 2026-07-28T20:00:00Z
)"
if [[ "$(wc -l <"$mock_log" | tr -d '[:space:]')" != "1" ||
  "$newer_queue_output" != *"newer authorization"* ]]; then
  echo "::error file=$script::a newer serialized merge-queue authorization must not be revoked by a stale rejected event"
  exit 1
fi

: >"$mock_log"
equal_time_output="$(
  MOCK_GH_LOG="$mock_log" MOCK_GH_STATE="PR_node_id true false 2026-07-28T20:00:00Z null" PATH="$mock_bin:$PATH" \
    bash "$script" devantler-tech/actions 42 2026-07-28T20:00:00Z
)"
if ! grep -Fq $'pr\tmerge\t42\t--disable-auto\t--repo\tdevantler-tech/actions' "$mock_log" ||
  [[ "$equal_time_output" != *"Auto-merge DISARMED"* ]]; then
  echo "::error file=$script::equal-time authorization is ambiguous and must revoke fail-closed"
  exit 1
fi

echo "disarm script revokes classic and merge-queue state, preserves no-op, and protects only proven newer authorization"
