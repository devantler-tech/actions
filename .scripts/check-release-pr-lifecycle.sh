#!/usr/bin/env bash

# Refuse to run Release Please when the most recently merged release PR has
# lost its lifecycle label.
#
# Release Please finds the release it just merged by the `autorelease: pending`
# label, then swaps it for `autorelease: tagged` once the tag exists. If that
# label is removed before the tag is cut, the next run cannot see the merged
# release PR: it re-scans the whole history, skips the pending version and
# opens a release PR for a version that was never intended (v12.0.2 became
# v13.0.0 this way — devantler-tech/actions#894).
#
# Input (stdin): the REST `pulls` list of ALL closed pull requests from the
# release branch, every page flattened into one array, as returned by
#   gh api --paginate --slurp "repos/<repo>/pulls?state=closed&head=<owner>:<branch>&per_page=100" | jq -c 'add // []'
# Every page matters: a release PR can be reopened and merged after newer ones
# were created, so the newest merge is not necessarily on the first page.
#
# Exit 0: no merged release PR yet, or the newest one carries a lifecycle label.
# Exit 1: the newest merged release PR carries neither lifecycle label.
# Exit 2: the input is not a pull request list, so nothing was checked.

set -euo pipefail

pending_label="autorelease: pending"
tagged_label="autorelease: tagged"

input="$(cat)"

# Validate every record, not just the container: a record whose labels are missing or malformed
# would otherwise read as "no lifecycle label" and report a missing label instead of bad input.
if ! jq -e 'type == "array" and all(.[];
      type == "object"
      and (.number | type) == "number"
      and (.merged_at == null or (.merged_at | type) == "string")
      and (.labels | type) == "array"
      and all(.labels[]; type == "object" and (.name | type) == "string"))' >/dev/null 2>&1 <<<"$input"; then
  echo "::error::release PR lifecycle check: input is not a well-formed pull request list, so the check did not run"
  exit 2
fi

latest="$(jq -c '[.[] | select(.merged_at != null)] | sort_by(.merged_at) | last' <<<"$input")"

if [[ "$latest" == "null" ]]; then
  echo "release PR lifecycle check: no merged release PR yet, nothing to check"
  exit 0
fi

number="$(jq -r '.number' <<<"$latest")"

if jq -e --arg pending "$pending_label" --arg tagged "$tagged_label" \
  '[.labels[]?.name] | any(. == $pending or . == $tagged)' >/dev/null <<<"$latest"; then
  echo "release PR lifecycle check: #${number} carries its lifecycle label"
  exit 0
fi

echo "::error::release PR #${number} was merged but carries neither '${pending_label}' nor '${tagged_label}'."
echo "::error::Release Please would not recognise it, re-scan history and propose an unintended version."
echo "::error::If #${number} has not been tagged yet, restore the label and re-run: gh pr edit ${number} --add-label '${pending_label}'"
echo "::error::If it was tagged already, record that instead: gh pr edit ${number} --add-label '${tagged_label}'"
exit 1
