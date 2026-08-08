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

  # Require a safe event predicate as the leading top-level conjunct. Merely
  # finding one elsewhere is unsafe: `true || event == pull_request` still
  # executes for merge_group and would make a substring-only guard vacuous.
  compact_condition="$(
    sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' <<<"$condition"
  )"
  expression="${compact_condition#\$\{\{}"
  expression="${expression#"${expression%%[![:space:]]*}"}"
  if [[ "$expression" == "github.event_name != 'merge_group' &&"* ||
    "$expression" == "github.event_name == 'push' &&"* ]]; then
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
  yq -o=json -I=0 \
    '.jobs.ci-required-checks.permissions' \
    "$ci"
)"
[[ "$required_permissions" == "{}" ]] ||
  fail "ci-required-checks must retain zero token permissions; got: $required_permissions"

required_job="$(yq -o=json -I=0 '.jobs.ci-required-checks' "$ci")"
if grep -qF 'secrets.' <<<"$required_job"; then
  fail "ci-required-checks must not receive repository secrets"
fi

echo "PASS: merge-group refs reach only the least-privileged required-check gate"
