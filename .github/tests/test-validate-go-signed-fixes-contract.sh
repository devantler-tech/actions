#!/usr/bin/env bash

# The org-required Go workflow may export three independently produced patches and then apply
# them serially. This guard pins the safety contract at that boundary: signed writes are opt-in,
# read-only validation still rejects a dirty tree, artifact names are invocation-unique, and a
# failed signer prevents every successor from writing on top of an uncertain branch tip.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"
ci_workflow="${2:-.github/workflows/ci.yaml}"
readme="${3:-README.md}"
apply_workflow="${4:-.github/workflows/apply-signed-fixes.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"
[[ -f "$ci_workflow" ]] || fail "CI workflow not found: $ci_workflow"
[[ -f "$readme" ]] || fail "README not found: $readme"
[[ -f "$apply_workflow" ]] || fail "apply-signed-fixes workflow not found: $apply_workflow"

input='.["on"].workflow_call.inputs."apply-signed-fixes"'
[[ "$(yq -r "${input}.type // \"\"" "$workflow")" == "boolean" ]] ||
  fail "apply-signed-fixes must be a boolean workflow_call input"
[[ "$(yq -r "${input}.default" "$workflow")" == "false" ]] ||
  fail "apply-signed-fixes must default to false; signed branch writes are rollout-gated"

flag_on='.jobs."test-validate-go-project-apply-signed-fixes"'
[[ "$(yq -r "${flag_on}.with.\"apply-signed-fixes\"" "$ci_workflow")" == "true" ]] ||
  fail "CI must instantiate apply-signed-fixes=true against the clean Go fixture"
[[ "$(yq -r "${flag_on}.with.\"working-directory\" // \"\"" "$ci_workflow")" == ".github/tests/go-valid-fixture" ]] ||
  fail "the apply-signed-fixes=true self-test must target the clean Go fixture"

grep -Eq '^\| `apply-signed-fixes`[[:space:]]+\| Input \(boolean\)[[:space:]]+\| `false`' "$readme" ||
  fail "README Validate Go Project inputs must document apply-signed-fixes default false"

dependency_bots='["dependabot[bot]","dependabot","renovate[bot]","renovatebot","renovate"]'

for job in tidy golangci-lint lint; do
  case "$job" in
    tidy) artifact_prefix=tidy-fixes ;;
    golangci-lint) artifact_prefix=golangci-lint-fixes ;;
    lint) artifact_prefix=megalinter-fixes ;;
  esac
  prepare="$(yq -r ".jobs.\"${job}\".steps[] | select(.id == \"fixes\")" "$workflow")"
  [[ "$(yq -r '.if // ""' <<<"$prepare")" == "" ]] ||
    fail "${job}'s fix detector must run in read-only mode too"

  [[ "$(yq -r '.env.FIXES_ARTIFACT // ""' <<<"$prepare")" == "${artifact_prefix}-\${{ job.check_run_id }}" ]] ||
    fail "${job} must pass its job.check_run_id-qualified artifact name through the environment"
  run_block="$(yq -r '.run // ""' <<<"$prepare")"
  grep -qF 'artifact-name=${FIXES_ARTIFACT}' <<<"$run_block" ||
    fail "${job} must emit the environment-qualified artifact name"
  grep -qF '${RUNNER_TEMP}/${FIXES_ARTIFACT}.patch' <<<"$run_block" ||
    fail "${job} must write the patch filename expected by its unique artifact name"

  artifact_output="$(yq -r ".jobs.\"${job}\".outputs.\"fixes-artifact\" // \"\"" "$workflow")"
  [[ "$artifact_output" == '${{ steps.fixes.outputs.artifact-name }}' ]] ||
    fail "${job} must expose the unique artifact name produced by its fixes step"

  upload="$(yq -r ".jobs.\"${job}\".steps[] | select((.uses // \"\") | contains(\"actions/upload-artifact@\"))" "$workflow")"
  [[ "$(yq -r '.with.name // ""' <<<"$upload")" == '${{ steps.fixes.outputs.artifact-name }}' ]] ||
    fail "${job}'s upload must use its invocation-unique artifact name"
  [[ "$(yq -r '.with.path // ""' <<<"$upload")" == '${{ runner.temp }}/${{ steps.fixes.outputs.artifact-name }}.patch' ]] ||
    fail "${job}'s patch filename must match its invocation-unique artifact name"
  upload_if="$(yq -r '.if // ""' <<<"$upload")"
  expected_upload_if="\${{ inputs.apply-signed-fixes == true && github.event_name == 'pull_request' && github.event.pull_request.head.repo.fork != true && !contains(fromJSON('${dependency_bots}'), github.event.pull_request.user.login) && !contains(fromJSON('${dependency_bots}'), inputs.pr-owner) && steps.fixes.outputs.changed == 'true' }}"
  [[ "$upload_if" == "$expected_upload_if" ]] ||
    fail "${job}'s artifact export must use the audited opt-in, same-repository PR gate"

  read_only="$(yq -r ".jobs.\"${job}\".steps[] | select(.name == \"❌ Fail if uncommitted changes remain (read-only mode)\")" "$workflow")"
  read_only_if="$(yq -r '.if // ""' <<<"$read_only")"
  expected_read_only_if="\${{ steps.fixes.outputs.changed == 'true' && (inputs.apply-signed-fixes != true || github.event_name != 'pull_request' || github.event.pull_request.head.repo.fork == true || contains(fromJSON('${dependency_bots}'), github.event.pull_request.user.login) || contains(fromJSON('${dependency_bots}'), inputs.pr-owner)) }}"
  [[ "$read_only_if" == "$expected_read_only_if" ]] ||
    fail "${job}'s dirty-tree gate must be the exact complement of the eligible write context"

  # Exercise the workflow's own dirty-tree block against a real repository. A clean tree must
  # pass and the same tree after a fixer edit must fail; this catches the previous silent pass.
  read_only_run="$(yq -r '.run // ""' <<<"$read_only")"
  fixture="$(mktemp -d)"
  git -C "$fixture" init -q
  git -C "$fixture" config user.email test@example.invalid
  git -C "$fixture" config user.name test
  git -C "$fixture" config commit.gpgsign false
  printf 'clean\n' >"$fixture/value.txt"
  git -C "$fixture" add value.txt
  git -C "$fixture" commit -qm base
  (cd "$fixture" && bash -euo pipefail -c "$read_only_run") ||
    fail "${job}'s read-only dirty-tree block rejects a clean tree"
  printf 'dirty\n' >"$fixture/value.txt"
  if (cd "$fixture" && bash -euo pipefail -c "$read_only_run") >/dev/null 2>&1; then
    fail "${job}'s read-only path silently accepts fixer changes"
  fi
  rm -rf "$fixture"
done

# The caller no longer skips the signer when its fixer produced nothing. It passes that fact in
# as `fixes-created`, because the branch tip still has to be checked in exactly that case: the
# replacement run after a cancelled committing run finds the work already done, so a caller-side
# skip made the called workflow's own tip check unreachable in the one scenario it was written
# for. These assertions pin both halves — the gate that no longer mentions fixes-created, and
# the input that now carries it — so neither can be quietly reintroduced as a skip.
for apply_job in apply-tidy-fixes apply-golangci-lint-fixes apply-fixes; do
  case "$apply_job" in
    apply-tidy-fixes) source_job=tidy ;;
    apply-golangci-lint-fixes) source_job=golangci-lint ;;
    apply-fixes) source_job=lint ;;
  esac
  [[ "$(yq -r ".jobs.\"${apply_job}\".with.\"artifact-name\" // \"\"" "$workflow")" == "\${{ needs.${source_job}.outputs.fixes-artifact }}" ]] ||
    fail "${apply_job} must consume the unique artifact name exposed by ${source_job}"
  apply_if="$(yq -r ".jobs.\"${apply_job}\".if // \"\"" "$workflow")"
  case "$apply_job" in
    apply-tidy-fixes)
      expected_apply_if="\${{ inputs.apply-signed-fixes == true }}"
      ;;
    apply-golangci-lint-fixes)
      expected_apply_if="\${{ !cancelled() && inputs.apply-signed-fixes == true && needs.golangci-lint.result == 'success' && (needs.apply-tidy-fixes.result == 'success' || needs.apply-tidy-fixes.result == 'skipped') }}"
      ;;
    apply-fixes)
      expected_apply_if="\${{ !cancelled() && inputs.apply-signed-fixes == true && needs.lint.result == 'success' && (needs.apply-golangci-lint-fixes.result == 'success' || needs.apply-golangci-lint-fixes.result == 'skipped') }}"
      ;;
  esac
  [[ "$apply_if" == "$expected_apply_if" ]] ||
    fail "${apply_job} must use the audited opt-in and predecessor-result gate"

  if grep -qF 'fixes-created' <<<"$apply_if"; then
    fail "${apply_job} must not gate the call on fixes-created; the tip check would be unreachable on a replacement run"
  fi

  [[ "$(yq -r ".jobs.\"${apply_job}\".with.\"fixes-created\" // \"\"" "$workflow")" == "\${{ needs.${source_job}.outputs.fixes-created == 'true' }}" ]] ||
    fail "${apply_job} must pass ${source_job}'s fixes-created through as an input"
done

# The called workflow's half of the same contract: the tip check must be reachable whatever the
# caller reports, and everything that needs the write-scoped App token must not be.
asf_input='.["on"].workflow_call.inputs."fixes-created"'
[[ "$(yq -r "${asf_input}.type // \"\"" "$apply_workflow")" == "boolean" ]] ||
  fail "apply-signed-fixes must expose fixes-created as a boolean workflow_call input"
[[ "$(yq -r "${asf_input}.default" "$apply_workflow")" == "true" ]] ||
  fail "fixes-created must default to true so an existing caller keeps its signing behaviour"

verify_step='.jobs."apply-fixes".steps[] | select(.name == "🔏 Verify an applied-fixes head is signed")'
[[ -n "$(yq -r "${verify_step}" "$apply_workflow")" ]] ||
  fail "apply-signed-fixes must carry the branch-tip signature check"
[[ "$(yq -r "${verify_step} | .if // \"\"" "$apply_workflow")" == "" ]] ||
  fail "the branch-tip signature check must be ungated; gating it recreates the unreachable-fallback defect"

for privileged_step in "🔑 Generate GitHub App Token" "📄 Checkout" "📥 Download applied fixes" "Apply fixes" "📤 Commit the applied fixes"; do
  step_if="$(yq -r ".jobs.\"apply-fixes\".steps[] | select(.name == \"${privileged_step}\") | .if // \"\"" "$apply_workflow")"
  [[ "$step_if" == "\${{ inputs.fixes-created == true }}" ]] ||
    fail "step '${privileged_step}' must be gated exactly '\${{ inputs.fixes-created == true }}': ungated, an absent artifact fails every clean pull request; written bare, a string-valued input would be truthy and run the privileged path anyway"
done


# Both states of `fixes-created` must be instantiated in CI, not merely declared. The false arm is
# the one that regresses silently: it is the only path on which the tip check runs alone, and a
# static assertion cannot tell whether the step actually executed. That job passes no App key, so
# it also fails if the gating regresses and the token step runs.
flag_off='.jobs."test-apply-signed-fixes-verifies-without-a-patch"'
[[ "$(yq -r "${flag_off}.with.\"fixes-created\"" "$ci_workflow")" == "false" ]] ||
  fail "CI must instantiate apply-signed-fixes with fixes-created=false, the arm where the tip check runs alone"
[[ "$(yq -r "${flag_off}.secrets // \"none\"" "$ci_workflow")" == "none" ]] ||
  fail "the fixes-created=false self-test must pass no App key; that absence is what makes a gating regression fail it"

echo "PASS: validate-go signed fixes are opt-in, collision-free, strict when read-only, and fail-closed in sequence"
