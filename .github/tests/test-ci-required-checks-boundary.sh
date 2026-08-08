#!/usr/bin/env bash
set -euo pipefail

workflow=${1:-.github/workflows/ci.yaml}
gate='.jobs.ci-required-checks'

fail() {
  printf 'ci-required-checks boundary: %s\n' "$1" >&2
  exit 1
}

[ -f "$workflow" ] || fail "workflow not found: $workflow"

permissions=$(yq -o=json -I=0 "$gate.permissions" "$workflow")
[ "$permissions" = '{}' ] ||
  fail "the required gate must have no token permissions, got: $permissions"

uses_steps=$(yq -r "$gate.steps[]? | select(.uses != null) | .uses" "$workflow")
[ -z "$uses_steps" ] ||
  fail "the required gate must not execute checked-out or external actions, got: $uses_steps"

step_count=$(yq -r "[$gate.steps[]? | select(.name == \"📊 Summarize workflow result\")] | length" "$workflow")
[ "$step_count" = '1' ] ||
  fail "expected exactly one inline summary step, got: $step_count"

script=$(yq -r "$gate.steps[] | select(.name == \"📊 Summarize workflow result\") | .run" "$workflow")
[ -n "$script" ] && [ "$script" != 'null' ] ||
  fail "the inline summary step has no executable script"

run_case() {
  local label=$1 input=$2 expected=$3 needle=$4 output rc=0

  output=$(JOB_RESULTS="$input" bash -c "$script" 2>&1) || rc=$?

  if [ "$expected" = pass ] && [ "$rc" -ne 0 ]; then
    fail "$label should pass, got exit $rc: $output"
  fi
  if [ "$expected" = fail ] && [ "$rc" -eq 0 ]; then
    fail "$label should fail closed, got exit 0: $output"
  fi
  if [[ "$output" != *"$needle"* ]]; then
    fail "$label should explain the result with '$needle', got: $output"
  fi
}

run_case 'success and skipped results' 'success skipped' pass 'all jobs succeeded or were skipped'
run_case 'failed result' 'success failure' fail 'failed or was cancelled'
run_case 'cancelled result' 'cancelled' fail 'failed or was cancelled'
run_case 'unknown result' 'success pending' fail "unknown job result: 'pending'"
run_case 'empty result list' '' fail 'no job results were provided'

printf 'ci-required-checks boundary and behavior are enforced\n'
