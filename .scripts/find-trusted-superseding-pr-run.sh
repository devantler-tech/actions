#!/usr/bin/env bash
# Read paginated Actions workflow-run JSON from stdin and print the actor only
# when the newest later pull_request run belongs to the same workflow and PR
# and that actor is explicitly trusted. Exit non-zero when no such
# reauthorization exists.
#
# Usage:
#   find-trusted-superseding-pr-run.sh \
#     <current-run-id> <workflow-id> <pr-number> <trusted-actors-json>

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <current-run-id> <workflow-id> <pr-number> <trusted-actors-json>" >&2
  exit 2
fi

current_run_id="$1"
workflow_id="$2"
pr_number="$3"
trusted_actors="$4"

jq -er \
  --argjson current "$current_run_id" \
  --argjson workflow "$workflow_id" \
  --argjson pr "$pr_number" \
  --argjson trusted "$trusted_actors" '
    [
      .[].workflow_runs[]?
      | select(
          (.id > $current) and
          (.workflow_id == $workflow) and
          any(.pull_requests[]?; .number == $pr)
        )
    ]
    | (if length == 0 then "" else (max_by(.id).actor.login // "") end) as $actor
    | select($actor != "" and ($trusted | index($actor)) != null)
    | $actor
  '
