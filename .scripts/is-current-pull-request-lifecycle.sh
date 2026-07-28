#!/usr/bin/env bash

# Determine whether a pull_request event is still the newest durable same-head
# lifecycle decision. Workflow concurrency cancels ordinary older work, but
# GitHub does not guarantee scheduling order within a concurrency group. The
# live head check in the workflow handles synchronize events; this helper
# detects later reopened/ready_for_review events without treating unrelated PR
# metadata edits as supersession.
#
# Exit 0: no later lifecycle event exists.
# Exit 1: a later lifecycle event exists.
# Exit 2: the event time or timeline input is malformed (fail closed).

set -euo pipefail

event_updated_at="${1:?usage: is-current-pull-request-lifecycle.sh <event-updated-at>}"
timeline="$(mktemp)"
trap 'rm -f "$timeline"' EXIT
tee "$timeline" >/dev/null

if ! jq -e --arg event_time "$event_updated_at" '
  ($event_time | fromdateiso8601) as $event_epoch
  | type == "array" and
    all(.[];
      (.type == "ReopenedEvent" or .type == "ReadyForReviewEvent") and
      (.createdAt | type == "string") and
      ((.createdAt | fromdateiso8601) != null)
    )
' "$timeline" >/dev/null 2>&1; then
  echo "::error::Malformed pull-request lifecycle timeline or event timestamp." >&2
  exit 2
fi

if jq -e --arg event_time "$event_updated_at" '
  ($event_time | fromdateiso8601) as $event_epoch
  | any(.[]; (.createdAt | fromdateiso8601) > $event_epoch)
' "$timeline" >/dev/null; then
  exit 1
fi

exit 0
