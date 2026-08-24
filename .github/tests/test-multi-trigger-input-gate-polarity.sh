#!/usr/bin/env bash

# A workflow_call input's `default:` is applied ONLY when the workflow is reached through
# `workflow_call`. validate-go-project.yaml is also reachable directly from `pull_request` and
# `merge_group` -- that is the org-required path, the one that runs on almost every consumer --
# and on those triggers the `inputs` context carries no defaults at all.
#
# So an input declared `default: true` and then read as a BARE TRUTHY value in an `if:` evaluates
# FALSE on exactly that path. The failure is silent and inverted: every self-test here calls the
# workflow through workflow_call, where the default IS applied, so the gate looks correct and
# stays green while the behaviour it guards is switched off for the entire organisation.
#
# That is not hypothetical -- it is the shape the signed-fixes migration was first written in
# (devantler-tech/.github#142), where `inputs.apply-fixes` defaulting to true would have stopped
# every consumer committing linter fixes while this repository's own CI passed.
#
# The repository's existing idiom for a multi-trigger input is an EXPLICIT comparison
# (`inputs.x == true || inputs.x == 'true'`, see test-default-branch), which is null-safe because
# an absent input simply fails both comparisons. The other safe shape is to phrase the input as an
# opt-OUT with `default: false`, so "absent" and "off" mean the same thing (see skip-apply-fixes).
#
# This guard pins that: in a workflow reachable from a non-workflow_call trigger, an input whose
# default is true is never read as a bare truthy value inside an `if:`.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"

# Only meaningful for a workflow reachable from more than just workflow_call. Asserted rather
# than assumed: if the extra triggers are ever removed this guard is vacuous, and a vacuous
# guard that still prints PASS is worse than no guard.
triggers="$(yq -r '.on | keys | .[]' "$workflow")"
non_call="$(grep -vcx 'workflow_call' <<<"$triggers" || true)"
[[ "$non_call" -gt 0 ]] ||
  fail "$workflow is workflow_call-only, so this guard asserts nothing; delete it or point it at a multi-trigger workflow"

default_true_inputs="$(
  yq -r '.on.workflow_call.inputs // {} | to_entries[] | select(.value.default == true) | .key' "$workflow"
)"

# Every if: expression in the file, job-level and step-level alike. Collected as compact JSON
# so a multi-line `if: |` block stays ONE item: read line-by-line, a block condition would be
# split across iterations and a violation spanning the break would never match.
# `mapfile` is deliberately not used -- it needs bash 4, and macOS ships 3.2.
conditions_json="$(
  yq -o=json -I=0 '[.jobs[].if // "", .jobs[].steps[]?.if // ""] | map(select(. != ""))' "$workflow"
)"
condition_count="$(jq 'length' <<<"$conditions_json")"
[[ "$condition_count" -gt 0 ]] ||
  fail "no if: expressions found in $workflow; this guard is not reading the file it thinks it is"

violations=0
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  i=0
  while [[ "$i" -lt "$condition_count" ]]; do
    cond="$(jq -r ".[$i]" <<<"$conditions_json" | tr '\n' ' ')"
    i=$((i + 1))
    # A bare read is `inputs.<name>` NOT followed by a comparison operator. An explicit
    # `== true` / `!= false` comparison is null-safe and is the accepted idiom.
    if grep -qE "inputs\.${name}[[:space:]]*(\)|&&|\|\||\}|$)" <<<"$cond"; then
      echo "  input '${name}' (default: true) is read as a bare truthy value in: ${cond}" >&2
      violations=$((violations + 1))
    fi
  done
done <<<"$default_true_inputs"

[[ "$violations" -eq 0 ]] ||
  fail "$workflow is reachable from a non-workflow_call trigger, where workflow_call defaults do NOT apply, so a default:true input read as a bare truthy value silently evaluates false on that path. Compare it explicitly (inputs.x == true || inputs.x == 'true') or phrase it as an opt-out with default:false."

echo "PASS: no default:true workflow_call input is read as a bare truthy gate in $workflow"
