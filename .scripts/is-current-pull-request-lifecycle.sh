#!/usr/bin/env bash

# Determine whether a pull_request event is still the newest durable same-head
# lifecycle decision. Workflow concurrency cancels ordinary older work, but
# GitHub does not guarantee scheduling order within a concurrency group. The
# live head check in the workflow handles synchronize events; this helper
# detects later reopened/ready_for_review events without treating unrelated PR
# metadata edits as supersession.
#
# Equal-second events are action-aware: reopened/ready_for_review may identify
# their own unique timeline item, while any additional equal-time item is
# ambiguous and fails closed as superseded.
#
# Exit 0: no later or ambiguous lifecycle event exists.
# Exit 1: a later or ambiguous lifecycle event exists.
# Exit 2: the event action, time, or timeline input is malformed (fail closed).

set -euo pipefail

event_action="${1:?usage: is-current-pull-request-lifecycle.sh <event-action> <event-updated-at>}"
event_updated_at="${2:?usage: is-current-pull-request-lifecycle.sh <event-action> <event-updated-at>}"
timeline="$(mktemp)"
trap 'rm -f "$timeline"' EXIT
tee "$timeline" >/dev/null

if ! jq -e --arg action "$event_action" --arg event_time "$event_updated_at" '
  (["opened", "synchronize", "reopened", "ready_for_review"] | index($action)) != null and
  ($event_time | fromdateiso8601) as $event_epoch
  | type == "array" and
    all(.[];
      (.type == "ReopenedEvent" or .type == "ReadyForReviewEvent") and
      (.createdAt | type == "string") and
      ((.createdAt | fromdateiso8601) != null)
    )
' "$timeline" >/dev/null 2>&1; then
  echo "::error::Malformed pull-request lifecycle action, timeline, or event timestamp." >&2
  exit 2
fi

if jq -e --arg action "$event_action" --arg event_time "$event_updated_at" '
  ($event_time | fromdateiso8601) as $event_epoch
  | any(.[]; (.createdAt | fromdateiso8601) > $event_epoch) or
    (
      [.[] | select((.createdAt | fromdateiso8601) == $event_epoch)] as $equal
      | if $action == "opened" or $action == "synchronize" then
          ($equal | length) > 0
        elif $action == "reopened" then
          ([$equal[] | select(.type == "ReopenedEvent")] | length) != 1 or
          ([$equal[] | select(.type == "ReadyForReviewEvent")] | length) != 0
        else
          ([$equal[] | select(.type == "ReadyForReviewEvent")] | length) != 1 or
          ($equal | length) != 1
        end
    )
' "$timeline" >/dev/null; then
  exit 1
fi

exit 0
