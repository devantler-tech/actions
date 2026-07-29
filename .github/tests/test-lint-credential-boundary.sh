#!/usr/bin/env bash

set -euo pipefail

lint_workflow="${1:-.github/workflows/lint.yaml}"
ci_workflow="${2:-.github/workflows/ci.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

caller_contents="$(
  yq -r '.jobs.test-lint-workflow.permissions.contents // ""' "$ci_workflow"
)"
[[ "$caller_contents" == "read" ]] ||
  fail "the clean-fixture caller must grant contents: read, found '${caller_contents:-unset}'"

caller_write_scopes="$(
  yq -r \
    '[.jobs.test-lint-workflow.permissions
      | to_entries[]
      | select(.value == "write")] | length' \
    "$ci_workflow"
)"
[[ "$caller_write_scopes" == "0" ]] ||
  fail "the clean-fixture caller must not grant any write-scoped GITHUB_TOKEN permission"

lint_contents="$(yq -r '.jobs.lint.permissions.contents // ""' "$lint_workflow")"
[[ "$lint_contents" == "read" ]] ||
  fail "the untrusted lint job must grant contents: read, found '${lint_contents:-unset}'"

lint_write_scopes="$(
  yq -r \
    '[.jobs.lint.permissions
      | to_entries[]
      | select(.value == "write")] | length' \
    "$lint_workflow"
)"
[[ "$lint_write_scopes" == "0" ]] ||
  fail "the untrusted lint job must not grant any write-scoped GITHUB_TOKEN permission"

lint_tokens="$(
  yq -r \
    '[.jobs.lint.steps[]
      | ..
      | select(tag == "!!str")
      | select(test("secrets\\.(GITHUB_TOKEN|APP_PRIVATE_KEY)|github\\.token"))] | length' \
    "$lint_workflow"
)"
[[ "$lint_tokens" == "0" ]] ||
  fail "the untrusted lint job must not receive the GitHub token or App private key"

persisted_checkouts="$(
  yq -r \
    '[.jobs.lint.steps[]
      | select((.uses // "") | contains("actions/checkout@"))
      | select(.with."persist-credentials" != false)] | length' \
    "$lint_workflow"
)"
[[ "$persisted_checkouts" == "0" ]] ||
  fail "every checkout in the untrusted lint job must set persist-credentials: false"

echo "PASS: MegaLinter runs behind a live read-only caller without repository credentials"
