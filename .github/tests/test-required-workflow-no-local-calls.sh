#!/usr/bin/env bash

# An organization-required workflow is compiled in each consumer repository. A job-level
# `uses: ./.github/workflows/...` therefore resolves in the consumer, not in this source
# repository, and GitHub rejects the workflow before it creates a single job.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"

consumer_relative_calls="$(
  yq -r '[.jobs[] | (.uses // "") | select(test("^\\./\\.github/workflows/"))] | .[]' \
    "$workflow"
)"

[[ -z "$consumer_relative_calls" ]] ||
  fail "required workflow contains consumer-relative reusable-workflow calls: ${consumer_relative_calls//$'\n'/, }"

expected_ref='devantler-tech/actions/.github/workflows/apply-signed-fixes.yaml@78ce1aca1e4736f4c4fe24975b085938805421f7'
for job in apply-tidy-fixes apply-golangci-lint-fixes apply-fixes; do
  actual_ref="$(yq -r ".jobs.\"${job}\".uses // \"\"" "$workflow")"
  [[ "$actual_ref" == "$expected_ref" ]] ||
    fail "${job} must call the signed-fixes workflow through the audited immutable source-repository reference"
done

echo "PASS: required workflow calls signed fixes through one immutable source-repository reference"
