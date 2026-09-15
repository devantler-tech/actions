#!/usr/bin/env bash
# Guards validate-go-project.yaml's concurrency group on the DEFAULT BRANCH
# (devantler-tech/ksail#6345).
#
# A default-branch run is the verification record for its commit. When runs on that branch
# share one concurrency group with cancel-in-progress, the next merge cancels the previous
# merge's validation. The path filter only looks at the latest push, so the surviving run
# skips build, lint and tidy for everything the cancelled run never finished, and the branch
# reports green over changes those checks never saw. Measured on ksail: 15 of 40 main push
# runs ended cancelled inside ✅ Validate Go Project.
#
# The group therefore carries `github.run_id` on the default branch, so no run there can
# cancel another, and only there, so a superseded pull-request or merge-queue run still
# cancels exactly as before. Three properties are asserted positively:
#
#   1. the default-branch clause selects `github.run_id`;
#   2. `github.run_id` appears nowhere else in the group, so it never becomes unconditional
#      (which would stop superseded pull-request runs from cancelling);
#   3. `github.ref` is still a discriminator and cancel-in-progress is still on, so
#      superseding off the default branch is preserved.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"
status=0

fail() {
  echo "::error file=$workflow::$1"
  status=1
}

group="$(yq -r '.concurrency.group // ""' "$workflow")"
cancel="$(yq -r '.concurrency."cancel-in-progress" | tostring' "$workflow")"
flat="$(tr -d '[:space:]' <<<"$group")"

default_branch_clause="\${{github.ref==format('refs/heads/{0}',github.event.repository.default_branch)&&github.run_id||''}}"

if [[ -z "$flat" ]]; then
  fail "no workflow-level concurrency group found, so default-branch runs cannot be kept from cancelling each other (ksail#6345)."
else
  if [[ "$flat" != *"$default_branch_clause"* ]]; then
    fail "the concurrency group has no default-branch clause selecting github.run_id, so each merge to the default branch cancels the previous merge's validation and its build, lint and tidy checks never run (ksail#6345). Expected the segment: $default_branch_clause"
  fi

  run_id_count="$(grep -o 'github\.run_id' <<<"$flat" | wc -l | tr -d ' ')"
  if [[ "$run_id_count" != "1" ]]; then
    fail "github.run_id appears $run_id_count times in the concurrency group; it must appear exactly once, inside the default-branch clause, or superseded pull-request runs stop cancelling (ksail#6345)."
  fi

  # shellcheck disable=SC2016 # the pattern is the workflow's literal ${{ }} text, never expanded
  if [[ "$flat" != *'${{github.ref}}'* ]]; then
    fail "the concurrency group no longer keys on github.ref, so runs for different pull requests would share a group and cancel each other."
  fi
fi

if [[ "$cancel" != "true" ]]; then
  fail "cancel-in-progress is '$cancel'; it must stay true so a superseded pull-request or merge-queue run is cancelled. The default branch is protected by its run-unique group, not by disabling cancellation."
fi

if [[ "$status" -eq 0 ]]; then
  echo "validate-go-project.yaml gives each default-branch run its own concurrency group and keeps superseding elsewhere ✅"
fi

exit "$status"
