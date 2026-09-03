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

# Every string the lint job can see, matched whole: the workflow-level `env:` it inherits,
# plus the complete job — a job-level `env:` reaches every step and would escape a
# steps-only walk. `github.token` is the same credential as `secrets.GITHUB_TOKEN`, so
# it is refused here in both spellings.
lint_token_refs() { # <workflow>
  yq -r \
    '[((.env // {}), .jobs.lint)
      | ..
      | select(tag == "!!str")
      | select(test("(?i)secrets[[:space:]]*(\\.|\\[)|github[[:space:]]*(\\.token|\\[[[:space:]]*[\"'"'"']token[\"'"'"'][[:space:]]*\\])|toJSON[[:space:]]*\\([[:space:]]*(secrets|github)"))] | length' \
    "$1"
}
lint_tokens="$(lint_token_refs "$lint_workflow")"
[[ "$lint_tokens" == "0" ]] ||
  fail "the untrusted lint job must not receive the GitHub token or App private key"

# Prove the scan reaches both inherited scopes: a token planted in the workflow-level env
# and one in the job-level env must each be counted, or the assertion above reads clean
# over a credential the lint job actually holds.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# shellcheck disable=SC2016 # literal Actions expressions handed to yq
for mutation in '.env.TOKEN = "${{ github.token }}"' '.jobs.lint.env.TOKEN = "${{ github.token }}"' '.jobs.lint.env.TOKEN = "${{ GITHUB.TOKEN }}"' '.jobs.lint.env.ALL = "${{ toJson(Secrets) }}"'; do
  yq "$mutation" "$lint_workflow" >"$work/mutant.yaml"
  [[ "$(lint_token_refs "$work/mutant.yaml")" == "1" ]] ||
    fail "the lint token scan must count a github.token planted with: $mutation"
done

echo "PASS: MegaLinter runs behind a live read-only caller without repository credentials"
