#!/usr/bin/env bash

set -euo pipefail

ci="${1:-.github/workflows/ci.yaml}"
standalone="${2:-.github/workflows/scan-for-workflow-vulnerabilities.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

standalone_triggers="$(yq -r '.on | keys | .[]' "$standalone" | sort | paste -sd, -)"
[[ "$standalone_triggers" == "merge_group,pull_request,workflow_call" ]] ||
  fail "standalone Zizmor gate must keep workflow_call, pull_request, and merge_group only; got: $standalone_triggers"

standalone_scan_count="$(
  yq -r \
    '[.jobs[].steps[]? | select((.uses // "") | test("^zizmorcore/zizmor-action@"))] | length' \
    "$standalone"
)"
[[ "$standalone_scan_count" == "1" ]] ||
  fail "standalone Zizmor gate must contain exactly one full-repository scan; found: $standalone_scan_count"

eligibility_has_condition="$(yq -r '.jobs.eligibility | has("if")' "$standalone")"
[[ "$eligibility_has_condition" == "false" ]] ||
  fail "standalone eligibility job must be unconditional"

eligibility_permissions="$(yq -r '(.jobs.eligibility.permissions // {}) | keys | join(",")' "$standalone")"
[[ -z "$eligibility_permissions" ]] ||
  fail "standalone eligibility job must have zero repository permissions; got: $eligibility_permissions"

eligibility_first_uses="$(yq -r '.jobs.eligibility.steps[0].uses // ""' "$standalone")"
eligibility_first_egress="$(yq -r '.jobs.eligibility.steps[0].with."egress-policy" // ""' "$standalone")"
[[ "$eligibility_first_uses" == "step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920" &&
  "$eligibility_first_egress" == "audit" ]] ||
  fail "standalone eligibility job must begin with the pinned harden-runner action in audit mode"

eligibility_output="$(yq -r '.jobs.eligibility.outputs.scan // ""' "$standalone")"
# shellcheck disable=SC2016 # GitHub expression is intentionally compared literally.
[[ "$eligibility_output" == '${{ steps.classify.outputs.scan }}' ]] ||
  fail "standalone eligibility output must be bound to steps.classify.outputs.scan"

classify_condition="$(yq -r '.jobs.eligibility.steps[] | select(.id == "classify") | .if // ""' "$standalone")"
[[ "$classify_condition" == "github.event_name != 'merge_group'" ]] ||
  fail "standalone scan classifier must exclude merge-group events; got: $classify_condition"

classify_run="$(yq -r '.jobs.eligibility.steps[] | select(.id == "classify") | .run // ""' "$standalone")"
# shellcheck disable=SC2016 # GitHub output path is intentionally compared literally.
[[ "$classify_run" == 'echo "scan=true" >> "$GITHUB_OUTPUT"' ]] ||
  fail "standalone scan classifier must explicitly emit scan=true; got: $classify_run"

no_op_condition="$(yq -r '.jobs.eligibility.steps[] | select(.id == "no-op") | .if // ""' "$standalone")"
[[ "$no_op_condition" == "steps.classify.outputs.scan != 'true'" ]] ||
  fail "standalone eligibility job must explicitly complete ineligible events as a successful no-op"

standalone_needs="$(yq -r '.jobs.zizmor.needs // ""' "$standalone")"
standalone_condition="$(yq -r '.jobs.zizmor.if // ""' "$standalone")"
[[ "$standalone_needs" == "eligibility" && "$standalone_condition" == "needs.eligibility.outputs.scan == 'true'" ]] ||
  fail "standalone privileged scan must depend on an exactly-true eligibility output"

ci_push_branches="$(yq -r '.on.push.branches | join(",")' "$ci")"
[[ "$ci_push_branches" == "main" ]] ||
  fail "CI must keep its main-push trigger for the default-branch Zizmor scan; got: $ci_push_branches"

reusable_scan_count="$(
  yq -r \
    '[.jobs[] | select(.uses == "./.github/workflows/scan-for-workflow-vulnerabilities.yaml")] | length' \
    "$ci"
)"
[[ "$reusable_scan_count" == "1" ]] ||
  fail "CI must contain exactly one reusable Zizmor workflow call; found: $reusable_scan_count"

test_zizmor_uses="$(yq -r '.jobs.test-zizmor.uses // ""' "$ci")"
[[ "$test_zizmor_uses" == "./.github/workflows/scan-for-workflow-vulnerabilities.yaml" ]] ||
  fail "test-zizmor must remain the reusable Zizmor workflow caller"

expected_test_condition="\${{ github.event_name == 'push' && !startsWith(github.head_ref, 'release-please--') && !startsWith(github.event.head_commit.message, 'chore(main): release ') }}"
test_zizmor_condition="$(yq -r '.jobs.test-zizmor.if // ""' "$ci")"
[[ "$test_zizmor_condition" == "$expected_test_condition" ]] ||
  fail "test-zizmor must be push-only with the release exclusions intact; got: $test_zizmor_condition"

direct_scan_jobs="$(
  yq -r '
    .jobs | to_entries[]
    | select([.value.steps[]? | select((.uses // "") | test("^zizmorcore/zizmor-action@"))] | length > 0)
    | .key
  ' "$ci" | sort
)"
[[ "$direct_scan_jobs" == "test-zizmor-blocks" ]] ||
  fail "CI's only direct Zizmor action must be the targeted failure-mode fixture; found jobs: ${direct_scan_jobs//$'\n'/,}"

fixture_scan_count="$(
  yq -r \
    '[.jobs.test-zizmor-blocks.steps[]? | select((.uses // "") | test("^zizmorcore/zizmor-action@"))] | length' \
    "$ci"
)"
[[ "$fixture_scan_count" == "1" ]] ||
  fail "test-zizmor-blocks must keep exactly one direct fixture scan; found: $fixture_scan_count"

fixture_inputs="$(
  yq -r \
    '.jobs.test-zizmor-blocks.steps[] | select((.uses // "") | test("^zizmorcore/zizmor-action@")) | .with.inputs // ""' \
    "$ci"
)"
fixture_continue="$(
  yq -r \
    '.jobs.test-zizmor-blocks.steps[] | select((.uses // "") | test("^zizmorcore/zizmor-action@")) | .["continue-on-error"] // false' \
    "$ci"
)"
fixture_advanced_security="$(
  yq -r \
    '.jobs.test-zizmor-blocks.steps[] | select((.uses // "") | test("^zizmorcore/zizmor-action@")) | .with["advanced-security"]' \
    "$ci"
)"
[[ "$fixture_inputs" == ".github/tests/zizmor-fixture/template-injection.yml" ]] ||
  fail "fixture scan must remain scoped to the deliberately vulnerable workflow; got: $fixture_inputs"
[[ "$fixture_continue" == "true" ]] ||
  fail "fixture scan must continue after the expected finding so its assertion can run"
[[ "$fixture_advanced_security" == "false" ]] ||
  fail "fixture finding must stay out of repository code scanning"

fixture_assertion="$(
  yq -r \
    '.jobs.test-zizmor-blocks.steps[] | select(.name == "✅ Assert the gate blocked on the vulnerable fixture") | .run // ""' \
    "$ci"
)"
# shellcheck disable=SC2016 # Match the literal workflow shell, not this test's variables.
grep -qF 'if [ "$OUTCOME" != "failure" ]' <<<"$fixture_assertion" ||
  fail "fixture assertion must prove the Zizmor action failed"
grep -qF 'template-injection' <<<"$fixture_assertion" ||
  fail "fixture assertion must distinguish a real finding from an operational failure"

expected_aggregate=$'test-zizmor\ntest-zizmor-action-lockstep\ntest-zizmor-blocks'
aggregate_needs="$(
  yq -r '.jobs.ci-required-checks.needs[] | select(test("zizmor"))' "$ci" | sort
)"
[[ "$aggregate_needs" == "$expected_aggregate" ]] ||
  fail "required-check needs must retain only the reusable and failure-mode Zizmor jobs; got: ${aggregate_needs//$'\n'/,}"

aggregate_results="$(
  yq -r '
    .jobs.ci-required-checks.steps[]
    | select(.uses == "./aggregate-job-checks")
    | .with["job-results"]
  ' "$ci" |
    grep -oE 'needs\.[a-z0-9-]*zizmor[a-z0-9-]*\.result' |
    sed -E 's/^needs\.//; s/\.result$//' |
    sort
)"
[[ "$aggregate_results" == "$expected_aggregate" ]] ||
  fail "required-check results must match the retained Zizmor jobs; got: ${aggregate_results//$'\n'/,}"

echo "PASS: Zizmor routing keeps one eligible full-repository scan plus the targeted failure-mode fixture"
