#!/usr/bin/env bash

set -euo pipefail

script="${1:-.scripts/is-current-pull-request-lifecycle.sh}"
fixtures="${2:-.github/tests/pull-request-lifecycle-events.json}"
status=0

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  event_updated_at="$(jq -r '.event_updated_at' <<<"$fixture")"
  expected_exit="$(jq -r '.expected_exit' <<<"$fixture")"

  set +e
  jq -c '.timeline' <<<"$fixture" | bash "$script" "$event_updated_at"
  actual_exit=$?
  set -e

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "::error file=$fixtures::fixture '$name' expected exit $expected_exit, got $actual_exit"
    status=1
  else
    echo "fixture '$name': exit=$actual_exit"
  fi
done < <(jq -c '.[]' "$fixtures")

exit "$status"
