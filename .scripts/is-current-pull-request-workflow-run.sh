#!/usr/bin/env bash
# Exit 0 only when no later pull_request run of this same workflow and PR
# exists in the paginated Actions response read from stdin.
#
# Exit 1 means a later run exists and must decide instead. Exit 2 means the
# input is malformed, which callers treat as a fail-closed ordering failure.

set -euo pipefail

if [[ $# -ne 3 || ! "$1" =~ ^[0-9]+$ || ! "$2" =~ ^[0-9]+$ || ! "$3" =~ ^[0-9]+$ ]]; then
  echo "usage: $0 <current-run-id> <workflow-id> <pr-number>" >&2
  exit 2
fi

current_run_id="$1"
workflow_id="$2"
pr_number="$3"
run_pages="$(cat)"

if ! jq -e '
  type == "array" and
  all(.[];
    type == "object" and
    (.workflow_runs | type) == "array" and
    all(.workflow_runs[];
      (.id | type) == "number" and
      (.workflow_id | type) == "number" and
      (.pull_requests | type) == "array" and
      all(.pull_requests[]; (.number | type) == "number")
    )
  )
' <<<"$run_pages" >/dev/null; then
  echo "::error::Workflow-run ordering response was malformed."
  exit 2
fi

if jq -e \
  --argjson current "$current_run_id" \
  --argjson workflow "$workflow_id" \
  --argjson pr "$pr_number" '
    any(
      .[].workflow_runs[];
      .id > $current and
      .workflow_id == $workflow and
      any(.pull_requests[]; .number == $pr)
    )
  ' <<<"$run_pages" >/dev/null; then
  exit 1
fi

exit 0
