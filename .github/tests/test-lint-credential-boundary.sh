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

# The workflow-scoped half — contents: read, no App token, no App key, persist-credentials: false —
# lives in test-fixer-credential-boundary.sh so the same assertions run against the org-required
# Go pipeline's three fixer lanes. What follows is the STRICTER set that only lint.yaml meets:
# no write scope of any kind and no GitHub token at all.
bash "$(dirname "${BASH_SOURCE[0]}")/test-fixer-credential-boundary.sh" "$lint_workflow" lint >/dev/null

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
      | select(test("secrets\\.GITHUB_TOKEN|github\\.token"))] | length' \
    "$lint_workflow"
)"
[[ "$lint_tokens" == "0" ]] ||
  fail "the untrusted lint job must not receive the GitHub token or App private key"

echo "PASS: MegaLinter runs behind a live read-only caller without repository credentials"
