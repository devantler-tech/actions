#!/usr/bin/env bash

set -euo pipefail

workflow="${1:-.github/workflows/template-sync.yaml}"
# GitHub evaluates this expression; the shell compares it as a literal contract.
# shellcheck disable=SC2016
expected_token='${{ steps.app-token.outputs.token || github.token }}'

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

step_count="$(
  yq -r \
    '[.jobs.template-sync.steps[] | select((.uses // "") | contains("AndreasAugustin/actions-template-sync@"))] | length' \
    "$workflow"
)"
[[ "$step_count" == "1" ]] || fail "expected exactly one actions-template-sync step, found $step_count"

source_token="$(
  yq -r \
    '.jobs.template-sync.steps[]
      | select((.uses // "") | contains("AndreasAugustin/actions-template-sync@"))
      | .with.source_gh_token // ""' \
    "$workflow"
)"
target_token="$(
  yq -r \
    '.jobs.template-sync.steps[]
      | select((.uses // "") | contains("AndreasAugustin/actions-template-sync@"))
      | .with.target_gh_token // ""' \
    "$workflow"
)"
deprecated_token="$(
  yq -r \
    '.jobs.template-sync.steps[]
      | select((.uses // "") | contains("AndreasAugustin/actions-template-sync@"))
      | .with.github_token // ""' \
    "$workflow"
)"

[[ "$source_token" == "$expected_token" ]] ||
  fail "source_gh_token must use the minted App token with the documented fallback"
[[ "$target_token" == "$expected_token" ]] ||
  fail "target_gh_token must use the minted App token so workflow-file pushes do not fall back to GITHUB_TOKEN"
[[ -z "$deprecated_token" ]] ||
  fail "deprecated github_token input must not mask missing source/target routing"

echo "PASS: Template Sync routes the minted App token to both source and target operations"
