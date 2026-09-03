#!/usr/bin/env bash
# Assert that a fixer lane holds no credential that can write to the branch it is linting.
#
#   bash .github/tests/test-fixer-credential-boundary.sh <workflow> <job> [<job> ...]
#
# A fixer lane runs tooling configured by the pull request under review — `go mod tidy`,
# `golangci-lint --fix`, MegaLinter — so anything it holds is reachable from PR-authored code.
# The commit is made elsewhere, on a fresh runner, by apply-signed-fixes.yaml. These are the
# WORKFLOW-SCOPED assertions: they read only the named workflow's jobs, so they can be pointed
# at any workflow, unlike the self-test-caller assertions that stay in
# test-lint-credential-boundary.sh.
#
# Deliberately NOT asserted here: that the job holds no GITHUB_TOKEN at all, or no write scope of
# any kind. The org-required Go pipeline's MegaLinter lane keeps `issues: write` and
# `pull-requests: write` for its reporters, and a token scoped `contents: read` cannot push. What
# is asserted is exactly what would restore a write path to the branch.

set -euo pipefail

workflow="${1:?usage: $0 <workflow> <job> [<job> ...]}"
shift
[[ $# -ge 1 ]] || { echo "usage: $0 <workflow> <job> [<job> ...]" >&2; exit 2; }

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

for job in "$@"; do
  yq -e ".jobs.\"${job}\"" "$workflow" >/dev/null 2>&1 ||
    fail "job '${job}' does not exist in ${workflow}; an assertion over a missing job proves nothing"

  contents="$(yq -r ".jobs.\"${job}\".permissions.contents // \"\"" "$workflow")"
  [[ "$contents" == "read" ]] ||
    fail "fixer lane '${job}' must grant contents: read, found '${contents:-unset}' — a write-scoped token here can push PR-authored changes"

  app_token_steps="$(
    yq -r \
      "[.jobs.\"${job}\".steps[]
        | select((.uses // \"\") | contains(\"create-github-app-token\"))] | length" \
      "$workflow"
  )"
  [[ "$app_token_steps" == "0" ]] ||
    fail "fixer lane '${job}' must not mint an App token — an installation token is valid on every repository the App is installed on"

  app_key_refs="$(
    yq -r \
      "[.jobs.\"${job}\".steps[]
        | ..
        | select(tag == \"!!str\")
        | select(test(\"secrets\\\\.APP_PRIVATE_KEY\"))] | length" \
      "$workflow"
  )"
  [[ "$app_key_refs" == "0" ]] ||
    fail "fixer lane '${job}' must not receive the App private key"

  persisted_checkouts="$(
    yq -r \
      "[.jobs.\"${job}\".steps[]
        | select((.uses // \"\") | contains(\"actions/checkout@\"))
        | select(.with.\"persist-credentials\" != false)] | length" \
      "$workflow"
  )"
  [[ "$persisted_checkouts" == "0" ]] ||
    fail "every checkout in fixer lane '${job}' must set persist-credentials: false, so the token is not left in the working tree the fixer runs in"
done

echo "PASS: fixer lane(s) $* in ${workflow} hold no credential that can write to the branch"
