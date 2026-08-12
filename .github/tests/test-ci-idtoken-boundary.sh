#!/usr/bin/env bash
# Guards this file's header rule for OIDC specifically: a job that can run on a
# pull_request checks out a PR-controlled workspace, including the local reusable
# workflows it calls, so granting it id-token: write lets a PR mint a real OIDC
# token. A called workflow gating its publish job on `if: ${{ !inputs.dry-run }}`
# is not a boundary — it is a property of the very file the PR may edit.

set -euo pipefail

ci="${1:-.github/workflows/ci.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# `permissions:` is either a MAP of scopes or the scalar shorthand `write-all`,
# which GitHub expands to write on every scope — id-token included. Reading only
# the map member returns empty for the scalar, so the shorthand would sail past
# a map-only check. Both shapes are resolved here and at job level below.
grants_id_token() {
  local tag=$1 raw=$2 member=$3
  [[ "$tag" == '!!str' && "$raw" == 'write-all' ]] && return 0
  [[ "$member" == 'write' ]] && return 0
  return 1
}

# A workflow-level grant is inherited by every job that does not override it, so
# it would defeat the per-job check below.
root_tag="$(yq -r '.permissions | tag' "$ci")"
root_raw="$(yq -r '.permissions | tostring' "$ci")"
root_idtoken="$(yq -r '.permissions."id-token" // ""' "$ci")"
if grants_id_token "$root_tag" "$root_raw" "$root_idtoken"; then
  fail "workflow-level permissions grant id-token: write, which pull_request-eligible jobs inherit"
fi

offenders=()
while IFS= read -r entry; do
  job="$(yq -r '.job' <<<"$entry")"
  condition="$(yq -r '.condition' <<<"$entry")"
  idtoken="$(yq -r '.idtoken' <<<"$entry")"
  ptag="$(yq -r '.ptag' <<<"$entry")"
  praw="$(yq -r '.praw' <<<"$entry")"

  grants_id_token "$ptag" "$praw" "$idtoken" || continue

  # Only a push-only job is exempt: its ref has already merged, so the workspace
  # is trusted. Classify on the LEADING top-level conjunct, matching
  # test-ci-merge-group-isolation.sh — a predicate that merely mentions the event
  # elsewhere (`true || github.event_name == 'push'`) still runs on a pull_request.
  # Anything unrecognised, including a job with no predicate, is treated as
  # pull_request-eligible, so this fails closed.
  compact_condition="$(
    sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' <<<"$condition"
  )"
  expression="${compact_condition#\$\{\{}"
  expression="${expression#"${expression%%[![:space:]]*}"}"
  if [[ "$expression" == "github.event_name == 'push' &&"* ||
    "$expression" == "github.event_name == 'push' }}"* ]]; then
    continue
  fi

  offenders+=("$job")
done < <(
  yq -o=json -I=0 \
    '.jobs | to_entries[] | {"job": .key, "condition": (.value.if // ""), "idtoken": (.value.permissions."id-token" // ""), "ptag": (.value.permissions | tag), "praw": (.value.permissions | tostring)}' \
    "$ci"
)

if ((${#offenders[@]} > 0)); then
  fail "pull_request-eligible jobs grant id-token: write to PR-editable workflows: ${offenders[*]}"
fi

echo "PASS: id-token: write is confined to push-only jobs"
