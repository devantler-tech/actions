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

local_calls="$(
  yq -r '[.jobs[] | (.uses // "") | select(test("^\\./\\.github/workflows/"))] | .[]' \
    "$workflow"
)"

[[ -z "$local_calls" ]] ||
  fail "required workflow contains consumer-relative reusable-workflow calls: ${local_calls//$'\n'/, }"

echo "PASS: required workflow contains no consumer-relative reusable-workflow calls"
