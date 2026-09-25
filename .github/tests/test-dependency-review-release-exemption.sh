#!/usr/bin/env bash
# The required dependency-review workflow may skip release-please's own pull requests, which
# only bump versions and the changelog. A head branch name is chosen by whoever opens the pull
# request, forks included, and the required-workflow rule reads a skipped run as passing, so the
# skip must also require a head branch in this repository (devantler-tech/.github#264).
set -euo pipefail

workflow="${1:-.github/workflows/dependency-review.yaml}"
fail() {
  echo "::error file=$workflow::$*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found"
condition="$(yq -r '.jobs.dependency-review.if' "$workflow")" || fail "could not read the job condition"
[[ -n "$condition" && "$condition" != null ]] || fail "the dependency-review job has no condition"

# shellcheck disable=SC2016  # a GitHub expression, not a shell one
expected='${{ (github.event_name == '"'"'pull_request'"'"' || github.event_name == '"'"'pull_request_target'"'"') && !(startsWith(github.head_ref, '"'"'release-please--'"'"') && github.event.pull_request.head.repo.full_name == github.repository) }}'
[[ "$condition" == "$expected" ]] ||
  fail "the dependency-review condition must skip only same-repository release-please pull requests; expected: $expected; found: $condition"

# No other job may skip on the branch name alone.
bare="$(yq -r '.jobs[].if // "" | select(test("startsWith\\(github\\.head_ref, .release-please--.\\)") and (test("head\\.repo\\.full_name == github\\.repository") | not))' "$workflow")" ||
  fail "could not read the job conditions"
[[ -z "$bare" ]] || fail "a job skips on a release-please branch name without requiring a same-repository head: $bare"

echo "PASS: dependency review skips only same-repository release-please pull requests"
