#!/usr/bin/env bash

# Exercises .scripts/check-release-pr-lifecycle.sh against fixed release PR
# lists. Each case asserts the exact exit code, so an input error (2) can never
# pass as a missing label (1) or a clean run (0).

set -euo pipefail

script="${1:-.scripts/check-release-pr-lifecycle.sh}"
fixtures="${2:-.github/tests/release-pr-lifecycle-cases.json}"
status=0
cases=0

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  expected_exit="$(jq -r '.expected_exit' <<<"$fixture")"

  set +e
  jq -c '.prs' <<<"$fixture" | bash "$script" >/dev/null
  actual_exit=$?
  set -e

  cases=$((cases + 1))
  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "::error file=$fixtures::case '$name' expected exit $expected_exit, got $actual_exit"
    status=1
  else
    echo "case '$name': exit=$actual_exit"
  fi
done < <(jq -c '.[]' "$fixtures")

# Empty stdin is not a pull request list either.
set +e
bash "$script" </dev/null >/dev/null
empty_exit=$?
set -e
cases=$((cases + 1))
if [[ "$empty_exit" -ne 2 ]]; then
  echo "::error::case 'empty input' expected exit 2, got $empty_exit"
  status=1
else
  echo "case 'empty input': exit=2"
fi

# A fixture file that yields no cases would make every assertion vacuous.
if [[ "$cases" -lt 10 ]]; then
  echo "::error file=$fixtures::only $cases case(s) ran; the fixture list is missing or unreadable"
  status=1
fi

exit "$status"
