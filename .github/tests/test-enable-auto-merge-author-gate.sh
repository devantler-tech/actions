#!/usr/bin/env bash

set -euo pipefail

workflow="${1:-.github/workflows/enable-auto-merge.yaml}"
fixtures="${2:-.github/tests/enable-auto-merge-authors.json}"
condition="$(yq -r '.jobs."auto-merge".if' "$workflow")"

status=0
for required_fragment in \
  "github.event_name == 'pull_request'" \
  "!github.event.pull_request.draft" \
  "github.event.pull_request.user.login"; do
  if [[ "$condition" != *"$required_fragment"* ]]; then
    echo "::error file=$workflow::auto-merge job condition is missing: $required_fragment"
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
  echo "::error file=$workflow::auto-merge job condition must use a JSON trusted-author allowlist"
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
