#!/usr/bin/env bash
# Prove test-fixer-credential-boundary.sh fires, and fires FOR THE RIGHT REASON, on each way a
# fixer lane could regain a write credential. Each mutation is applied to a copy of the real
# org-required Go workflow, and the assertion's failure message must name that mutation's
# specific cause — a rejection for some incidental reason would read as protection while
# asserting nothing.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
assertion="$repo_root/.github/tests/test-fixer-credential-boundary.sh"
workflow="$repo_root/.github/workflows/validate-go-project.yaml"
# The fixer lanes are the jobs that export a patch for apply-signed-fixes.yaml. Deriving them
# means a fourth fixer lane is covered by construction instead of by someone remembering.
lanes=()
while IFS= read -r lane; do
  [[ -n "$lane" ]] && lanes+=("$lane")
done < <(yq -r '.jobs | to_entries[] | select(.value.outputs."fixes-created") | .key' "$workflow")
[[ ${#lanes[@]} -ge 1 ]] || { echo "FAIL: no fixer lane exports fixes-created; the assertion would run over nothing" >&2; exit 1; }

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Control: the real workflow passes, so a rejection below is caused by the mutation.
bash "$assertion" "$workflow" "${lanes[@]}" >/dev/null ||
  fail "control: the unmodified workflow must pass the assertion"

expect_rejected() { # <description> <yq-mutation> <required-message-fragment>
  local description="$1" mutation="$2" fragment="$3" out
  yq "$mutation" "$workflow" >"$work/mutant.yaml"
  if out="$(bash "$assertion" "$work/mutant.yaml" "${lanes[@]}" 2>&1)"; then
    fail "mutation passed: $description"
  fi
  grep -qF -- "$fragment" <<<"$out" ||
    fail "mutation '$description' was rejected, but not for its own reason; got: $out"
  echo "ok: rejected — $description"
}

expect_rejected 'a lane regains contents: write' \
  '.jobs.tidy.permissions.contents = "write"' \
  'must grant contents: read'
expect_rejected 'a lane drops its contents permission entirely' \
  'del(.jobs."golangci-lint".permissions.contents)' \
  'must grant contents: read'
expect_rejected 'a lane mints an App token' \
  '.jobs."golangci-lint".steps += [{"name": "token", "uses": "actions/create-github-app-token@0000000000000000000000000000000000000000"}]' \
  'must not mint an App token'
# shellcheck disable=SC2016 # the ${{ }} is a literal Actions expression handed to yq, not a shell expansion
expect_rejected 'a lane receives the App private key' \
  '.jobs.lint.steps[0].env.KEY = "${{ secrets.APP_PRIVATE_KEY }}"' \
  'must not receive the App private key'
# shellcheck disable=SC2016 # literal Actions expression handed to yq
expect_rejected 'a lane receives the App private key at job level' \
  '.jobs.tidy.env.KEY = "${{ secrets.APP_PRIVATE_KEY }}"' \
  'must not receive the App private key'
# shellcheck disable=SC2016 # literal Actions expression handed to yq
expect_rejected 'a lane hands a PAT to its checkout' \
  '(.jobs.lint.steps[] | select(.uses | test("actions/checkout@")) | .with.token) = "${{ secrets.BOT_PAT }}"' \
  'any secret other than GITHUB_TOKEN'
expect_rejected 'a lane persists the token into its checkout' \
  '(.jobs.lint.steps[] | select(.uses | test("actions/checkout@")) | .with."persist-credentials") = true' \
  'persist-credentials: false'
expect_rejected 'a lane named for assertion does not exist' \
  'del(.jobs.tidy)' \
  'does not exist'

echo "PASS: fixer credential boundary assertion fires for its own reason on 8 mutations"
