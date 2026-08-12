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

# `&&` binds tighter than `||`, so `<push-check> && false || true` parses as
# `(<push-check> && false) || true` — true on a pull_request however the
# predicate opens. A leading push-only conjunct therefore proves nothing once a
# top-level disjunction follows it, and classifying on that conjunct alone is a
# fail-open. Only a disjunction the leading conjunct cannot bypass counts:
# `||` inside parentheses is a sub-expression the conjunct still gates, and one
# inside a single-quoted literal is not an operator at all. Doubled quotes are
# GitHub's escape for a literal quote and toggle in pairs, so tracking the
# string state alone reads them correctly.
has_top_level_or() {
  local expr=$1 i ch depth=0 in_str=0
  for ((i = 0; i < ${#expr}; i++)); do
    ch="${expr:i:1}"
    if ((in_str)); then
      [[ "$ch" == "'" ]] && in_str=0
      continue
    fi
    case "$ch" in
      "'") in_str=1 ;;
      '(') ((depth++)) ;;
      ')') ((depth > 0)) && ((depth--)) ;;
      '|') [[ "${expr:i+1:1}" == '|' ]] && ((depth == 0)) && return 0 ;;
    esac
  done
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
  # elsewhere (`true || github.event_name == 'push'`) still runs on a pull_request
  # — and require that no top-level disjunction follows it, which would otherwise
  # short-circuit past that conjunct entirely. Anything unrecognised, including a
  # job with no predicate, is treated as pull_request-eligible, so this fails
  # closed.
  compact_condition="$(
    sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' <<<"$condition"
  )"
  # Only a scalar that is EXACTLY one interpolation carries the expression's
  # boolean. `${{ <expr> }}<suffix>` is a string: on a pull_request the
  # interpolation renders `false` and the scalar becomes `falsesuffix`, which
  # Actions evaluates as true — so a suffixed predicate runs on every event
  # however push-only its expression looks. The closing `}}` must therefore be
  # the first one and must end the scalar; anything else is left unrecognised
  # and stays pull_request-eligible.
  body="${compact_condition#\$\{\{}"
  expression="${body%%\}\}*}"
  [[ "${body#"$expression"}" == '}}' ]] || expression=''
  expression="${expression#"${expression%%[![:space:]]*}"}"
  expression="${expression%"${expression##*[![:space:]]}"}"
  if [[ -n "$expression" ]] &&
    [[ "$expression" == "github.event_name == 'push' &&"* ||
    "$expression" == "github.event_name == 'push'" ]] &&
    ! has_top_level_or "$expression"; then
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
