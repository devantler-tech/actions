#!/usr/bin/env bash

# create-release.yaml must run one release at a time per repository and ref, and must keep every
# queued run (#970). Two overlapping semantic-release runs can compute the same next version, so
# the second fails on the tag the first created and its commits miss the release. A queued run
# that is cancelled or replaced is the same lost release, so cancellation stays off and the
# queue keeps every pending run instead of only the newest.
#
# The block lives on the release job of the reusable workflow, so every caller inherits it
# without declaring its own. github.repository and github.ref resolve to the caller's values.

set -euo pipefail

workflow="${1:-.github/workflows/create-release.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"

concurrency='.jobs.release.concurrency'

expected_group="create-release-\${{ github.repository }}-\${{ github.ref }}"
group="$(yq -r "${concurrency}.group // \"\"" "$workflow")"
[[ "$group" == "$expected_group" ]] ||
  fail "the release job must serialize on '${expected_group}' (found '${group}'); without a per-repository, per-ref group, overlapping merges race for the same version"

cancel="$(yq -r "${concurrency}.\"cancel-in-progress\"" "$workflow")"
[[ "$cancel" == "false" ]] ||
  fail "the release job must set cancel-in-progress: false (found '${cancel}'); cancelling a running release loses it"

queue="$(yq -r "${concurrency}.queue // \"\"" "$workflow")"
[[ "$queue" == "max" ]] ||
  fail "the release job must set queue: max (found '${queue}'); the default single queue cancels a pending release when a newer one arrives"

echo "create-release serializes release runs per repository and ref without dropping queued runs"
