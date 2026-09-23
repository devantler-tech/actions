#!/usr/bin/env bash

# A workflow_call input's `default:` is applied ONLY when the workflow is reached through
# `workflow_call`. validate-go-project.yaml is also reachable directly from `pull_request` and
# `merge_group` -- that is the org-required path, the one that runs on almost every consumer --
# and on those triggers the `inputs` context carries no defaults at all.
#
# So an input declared `default: true` and then read as a BARE TRUTHY value evaluates FALSE (or
# empty) on exactly that path. The failure is silent and inverted: every self-test here calls the
# workflow through workflow_call, where the default IS applied, so the gate looks correct and
# stays green while the behaviour it guards is switched off for the entire organisation.
#
# That is not hypothetical -- it is the shape the signed-fixes migration was first written in
# (devantler-tech/.github#142), where `inputs.apply-fixes` defaulting to true would have stopped
# every consumer committing linter fixes while this repository's own CI passed. lint.yaml still
# carries that shape verbatim in an `env:` value (APPLY_FIXES), correctly, because lint.yaml is
# workflow_call-only; this guard exists to stop it being carried into a multi-trigger workflow.
#
# The repository's existing idiom for a multi-trigger input is an EXPLICIT comparison
# (`inputs.x == true || inputs.x == 'true'`, see test-default-branch), which is null-safe because
# an absent input simply fails both comparisons. The other safe shape is to phrase the input as an
# opt-OUT with `default: false`, so "absent" and "off" mean the same thing (see skip-apply-fixes).
#
# This guard pins that: in a workflow reachable from a non-workflow_call trigger, an input whose
# default is true is never read as a bare truthy value in ANY evaluated expression -- every
# job/step `if:` plus every `${{ ... }}` in any string scalar (`env:`, `with:`, `run:`, outputs,
# ...). An explicit comparison is accepted with the input on either side of the operator.
# test-multi-trigger-input-gate-polarity-ablation.sh proves each of those properties on fixtures.

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

# Same non-vacuity rule as the trigger and condition sets above, and for the same reason: with no
# default:true input the loop below never runs, `violations` stays 0 and this prints PASS while
# asserting nothing. The set is non-empty today only because `test-default-branch` defaults to
# true, and ci.yaml names this script as the static substitute for a recorded coverage gap — so a
# flipped default would silently retire that coverage rather than fail.
[[ -n "${default_true_inputs//[[:space:]]/}" ]] ||
  fail "$workflow declares no default:true workflow_call input, so this guard asserts nothing; delete it or point it at a workflow that has one"

# Every evaluated expression in the file, one pre-flattened line each:
#   * every `${{ ... }}` segment of every string scalar -- `env:`, `with:`, `run:`, outputs --
#     not only `if:`, because a bare read in `env:` is just as false on the direct path;
#   * every job- and step-level `if:` in full, since `if:` may omit the `${{ }}` wrapper.
# Whitespace, including the line breaks of an `if: |` block, is collapsed first so a condition
# spanning lines stays ONE item and a violation across the break still matches. Duplicates (an
# `if: ${{ }}` is found both ways) are dropped. Only the expression is kept, so shell text around
# a `${{ }}` in a `run:` block can never match by accident.
#
# Concurrency GROUP keys are skipped: a group is an identity string, so an input interpolated
# into it changes the key's spelling on the direct path but gates nothing. `cancel-in-progress`
# is NOT skipped -- it is a boolean that a bare read would silently turn off.
#
# `mapfile` is deliberately not used -- it needs bash 4, and macOS ships 3.2.
# shellcheck disable=SC2016 # jq program text, never a shell expansion
expressions_jq='
  def is_if:
    (.p | length) as $n
    | ($n == 3 and .p[0] == "jobs" and .p[2] == "if")
      or ($n == 5 and .p[0] == "jobs" and .p[2] == "steps" and .p[4] == "if");
  def is_concurrency_group:
    (.p == ["concurrency"]) or (.p == ["concurrency", "group"])
    or ((.p | length) == 3 and .p[0] == "jobs" and .p[2] == "concurrency")
    or ((.p | length) == 4 and .p[0] == "jobs" and .p[2] == "concurrency" and .p[3] == "group");
  [ .[]
    | select(is_concurrency_group | not)
    | (.v | gsub("\\s+"; " ")) as $flat
    | if ($flat | contains("${{")) then ($flat | scan("\\$\\{\\{.*?\\}\\}"))
      elif is_if then $flat
      else empty end
  ] | unique | .[]
'
conditions="$(
  yq -o=json -I=0 '[.. | select(tag == "!!str") | {"p": path, "v": .}]' "$workflow" |
    jq -r "$expressions_jq"
)"
condition_count="$(grep -c . <<<"$conditions" || true)"
[[ "$condition_count" -gt 0 ]] ||
  fail "no expressions found in $workflow; this guard is not reading the file it thinks it is"

violations=0
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  while IFS= read -r cond; do
    [[ -n "$cond" ]] || continue
    # An explicit comparison is null-safe with the input on EITHER side. Neutralise the
    # right-operand form first (`X == inputs.NAME`), so the forward check below judges only the
    # occurrences that remain -- one explicit comparison must not excuse a second, bare read in
    # the same expression.
    remaining="$(sed -E "s/(==|!=|<=|>=|<|>)[[:space:]]*inputs\.${name}([^A-Za-z0-9_-]|$)/<compared>\2/g" <<<"$cond")"
    # A bare read is `inputs.<name>` NOT followed by a comparison operator. An explicit
    # `== true` / `!= false` comparison is null-safe and is the accepted idiom.
    if grep -qE "inputs\.${name}[[:space:]]*(\)|&&|\|\||\}|$)" <<<"$remaining"; then
      echo "  input '${name}' (default: true) is read as a bare truthy value in: ${cond}" >&2
      violations=$((violations + 1))
    fi
  done <<<"$conditions"
done <<<"$default_true_inputs"

[[ "$violations" -eq 0 ]] ||
  fail "$workflow is reachable from a non-workflow_call trigger, where workflow_call defaults do NOT apply, so a default:true input read as a bare truthy value silently evaluates false on that path. Compare it explicitly (inputs.x == true || inputs.x == 'true') or phrase it as an opt-out with default:false."

echo "PASS: no default:true workflow_call input is read as a bare truthy value in $workflow (${condition_count} expressions scanned)"
