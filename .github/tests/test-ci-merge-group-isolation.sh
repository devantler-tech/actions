#!/usr/bin/env bash

set -euo pipefail

ci="${1:-.github/workflows/ci.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

unsafe_jobs=()
while IFS= read -r entry; do
  job="$(yq -r '.job' <<<"$entry")"
  condition="$(yq -r '.condition' <<<"$entry")"
  [[ "$job" == "ci-required-checks" ]] && continue

  # Every job that consumes the merge ref must make its exclusion explicit.
  # Jobs already restricted to pull-request or push events are also ineligible.
  if [[ "$condition" == *"merge_group"* &&
    "$condition" != *"github.event_name != 'merge_group'"* ]]; then
    unsafe_jobs+=("$job")
    continue
  fi

  if [[ "$condition" == *"github.event_name != 'merge_group'"* ||
    "$condition" == *"github.event_name == 'pull_request'"* ||
    "$condition" == *"github.event_name == 'push'"* ||
    "$condition" == *"startsWith(github.event_name, 'pull_request')"* ]]; then
    continue
  fi

  unsafe_jobs+=("$job")
done < <(
  yq -o=json -I=0 \
    '.jobs | to_entries[] | {"job": .key, "condition": (.value.if // "")}' \
    "$ci"
)

if ((${#unsafe_jobs[@]} > 0)); then
  fail "jobs may execute merge-group-controlled code: ${unsafe_jobs[*]}"
fi

required_condition="$(yq -r '.jobs.ci-required-checks.if // ""' "$ci")"
# shellcheck disable=SC2016 # GitHub expression is intentionally compared literally.
[[ "$required_condition" == '${{ always() }}' ]] ||
  fail "ci-required-checks must remain the always-running merge-queue completion gate"

required_permissions="$(
  yq -r \
    '.jobs.ci-required-checks.permissions | to_entries | map(.key + "=" + .value) | sort | join(",")' \
    "$ci"
)"
[[ "$required_permissions" == "contents=read" ]] ||
  fail "ci-required-checks must retain only contents=read; got: $required_permissions"

required_job="$(yq -o=json -I=0 '.jobs.ci-required-checks' "$ci")"
if grep -qF 'secrets.' <<<"$required_job"; then
  fail "ci-required-checks must not receive repository secrets"
fi

echo "PASS: merge-group refs reach only the least-privileged required-check gate"
