#!/usr/bin/env bash

set -euo pipefail

workflow="${1:-.github/workflows/enable-auto-merge.yaml}"
fixtures="${2:-.github/tests/enable-auto-merge-authors.json}"
condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "classify")
   | .if // ""]
  | join("\n")' "$workflow")"

status=0

# A required workflow must complete successfully for ineligible events rather
# than making its only job SKIPPED. Keep classification in an unconditional,
# zero-permission job and gate the privileged job on its output.
eligibility_job_condition="$(yq -r '.jobs.eligibility.if // ""' "$workflow")"
if [[ -n "$eligibility_job_condition" ]]; then
  echo "::error file=$workflow::eligibility job must be unconditional so required workflows complete for ineligible events"
  status=1
fi

eligibility_permissions="$(yq -r '(.jobs.eligibility.permissions // {}) | keys | join(",")' "$workflow")"
if [[ -n "$eligibility_permissions" ]]; then
  echo "::error file=$workflow::eligibility job must not request repository permissions; got: $eligibility_permissions"
  status=1
fi

eligibility_output="$(yq -r '.jobs.eligibility.outputs.eligible // ""' "$workflow")"
# shellcheck disable=SC2016 # GitHub expression is intentionally compared literally.
if [[ "$eligibility_output" != '${{ steps.classify.outputs.eligible }}' ]]; then
  echo "::error file=$workflow::eligibility output must be bound to steps.classify.outputs.eligible"
  status=1
fi

ineligible_condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "ineligible")
   | .if // ""]
  | join("\n")' "$workflow")"
if [[ "$ineligible_condition" != *"steps.classify.outputs.eligible != 'true'"* ]]; then
  echo "::error file=$workflow::eligibility job needs an explicit successful ineligible-event step"
  status=1
fi

auto_merge_needs="$(yq -r '.jobs."auto-merge".needs // ""' "$workflow")"
auto_merge_condition="$(yq -r '.jobs."auto-merge".if // ""' "$workflow")"
if [[ "$auto_merge_needs" != "eligibility" ||
  "$auto_merge_condition" != *"needs.eligibility.outputs.eligible == 'true'"* ]]; then
  echo "::error file=$workflow::privileged auto-merge job must depend on the eligibility output"
  status=1
fi

eligibility_uses="$(yq -r '[(.jobs.eligibility.steps // [])[] | .uses // ""] | join("\n")' "$workflow")"
if [[ "$eligibility_uses" == *"create-github-app-token"* ]]; then
  echo "::error file=$workflow::ineligible events must not mint a privileged GitHub App token"
  status=1
fi

for required_fragment in \
  "github.event_name == 'pull_request'" \
  "!github.event.pull_request.draft" \
  "github.event.pull_request.user.login"; do
  if [[ "$condition" != *"$required_fragment"* ]]; then
    echo "::error file=$workflow::eligibility classifier is missing: $required_fragment"
    status=1
  fi
done

allowlist_json="$({
  printf '%s\n' "$condition" |
    tr -d '[:space:]' |
    sed -nE "s/.*contains\(fromJSON\('([^']+)'\),github\.event\.pull_request\.user\.login\).*/\1/p"
} || true)"
if [[ -z "$allowlist_json" ]] || ! jq -e 'type == "array" and all(.[]; type == "string")' \
  <<<"$allowlist_json" >/dev/null; then
  echo "::error file=$workflow::eligibility classifier must use a JSON trusted-author allowlist"
  exit 1
fi

actual_allowlist="$(jq -c 'sort' <<<"$allowlist_json")"
expected_allowlist="$(jq -c '[.[] | select(.eligible) | .login] | sort' "$fixtures")"
if [[ "$actual_allowlist" != "$expected_allowlist" ]]; then
  echo "::error file=$workflow::trusted-author allowlist differs from the eligible fixture authors"
  echo "expected: $expected_allowlist"
  echo "actual:   $actual_allowlist"
  status=1
fi

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  event_name="$(jq -r '.event_name' <<<"$fixture")"
  draft="$(jq -r '.draft' <<<"$fixture")"
  login="$(jq -r '.login' <<<"$fixture")"
  expected="$(jq -r '.eligible' <<<"$fixture")"
  actual=false

  if [[ "$event_name" == "pull_request" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null; then
    actual=true
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "::error file=$fixtures::fixture '$name' expected eligible=$expected, got $actual"
    status=1
  else
    echo "fixture '$name': eligible=$actual"
  fi
done < <(jq -c '.[]' "$fixtures")

exit "$status"
