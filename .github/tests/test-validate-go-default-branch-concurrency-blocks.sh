#!/usr/bin/env bash
# Failing-input counterpart to test-validate-go-default-branch-concurrency.sh
# (devantler-tech/ksail#6345).
#
# Builds each bad variant from the REAL workflow, so the fixtures cannot drift from it, and
# asserts the guard fails with the message for that variant. It also asserts the guard
# passes the real workflow, so neither an accept-everything nor a reject-everything guard
# passes this test.

set -euo pipefail
# Bash 5.2 expands an unquoted-looking `&` in a ${var//pattern/replacement} replacement to the
# matched text; the clause contains `&&`, so the variants below would be built corrupted.
shopt -u patsub_replacement 2>/dev/null || true

workflow="${1:-.github/workflows/validate-go-project.yaml}"
guard="$(dirname "$0")/test-validate-go-default-branch-concurrency.sh"
clause="-\${{ github.ref == format('refs/heads/{0}', github.event.repository.default_branch) && github.run_id || '' }}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
status=0

content="$(cat "$workflow")"
if [[ "$content" != *"$clause"* ]]; then
  echo "::error file=$workflow::the default-branch clause was not found verbatim, so no bad variant can be built from it."
  exit 1
fi

expect_fail() {
  local name="$1" file="$2" message="$3" out
  if out="$(bash "$guard" "$file" 2>&1)"; then
    echo "::error::guard PASSED the '$name' variant; it must fail."
    status=1
  elif [[ "$out" != *"$message"* ]]; then
    echo "::error::guard failed the '$name' variant for the wrong reason. Expected '$message', got: $out"
    status=1
  else
    echo "blocks '$name' ✅"
  fi
}

if ! out="$(bash "$guard" "$workflow" 2>&1)"; then
  echo "::error::guard rejects the real workflow: $out"
  status=1
fi

# 1. The defect itself: default-branch runs share one group again.
printf '%s\n' "${content//"$clause"/}" >"$tmp/no-clause.yaml"
expect_fail "no default-branch clause" "$tmp/no-clause.yaml" "no default-branch clause selecting github.run_id"

# 2. run_id made unconditional: pull-request runs stop superseding.
unconditional="$clause-\${{ github.run_id }}"
# The replacement stays unquoted: bash 3.2 keeps quotes there literally.
printf '%s\n' "${content//"$clause"/$unconditional}" >"$tmp/unconditional.yaml"
expect_fail "unconditional run_id" "$tmp/unconditional.yaml" "must appear exactly once"

# 3. github.ref dropped as a discriminator.
# shellcheck disable=SC2016 # the pattern is the workflow's literal ${{ }} text, never expanded
printf '%s\n' "${content//'-${{ github.ref }}-'/-}" >"$tmp/no-ref.yaml"
expect_fail "no github.ref" "$tmp/no-ref.yaml" "no longer keys on github.ref"

# 4. Cancellation switched off instead of isolating the default branch.
yq '.concurrency."cancel-in-progress" = false' "$workflow" >"$tmp/no-cancel.yaml"
expect_fail "cancel-in-progress off" "$tmp/no-cancel.yaml" "cancel-in-progress is 'false'"

exit "$status"
