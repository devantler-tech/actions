#!/usr/bin/env bash

# The org-required Go workflow may export three independently produced patches and then apply
# them serially. This guard pins the safety contract at that boundary: signed writes are opt-in,
# read-only validation still rejects a dirty tree, artifact names are invocation-unique, and a
# failed signer prevents every successor from writing on top of an uncertain branch tip.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"
ci_workflow="${2:-.github/workflows/ci.yaml}"
readme="${3:-README.md}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$workflow" ]] || fail "workflow not found: $workflow"
[[ -f "$ci_workflow" ]] || fail "CI workflow not found: $ci_workflow"
[[ -f "$readme" ]] || fail "README not found: $readme"

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
  expected_upload_if="\${{ inputs.apply-signed-fixes == true && github.event_name == 'pull_request' && github.event.pull_request.head.repo.fork != true && steps.fixes.outputs.changed == 'true' }}"
  [[ "$upload_if" == "$expected_upload_if" ]] ||
    fail "${job}'s artifact export must use the audited opt-in, same-repository PR gate"

  read_only="$(yq -r ".jobs.\"${job}\".steps[] | select(.name == \"❌ Fail if uncommitted changes remain (read-only mode)\")" "$workflow")"
  read_only_if="$(yq -r '.if // ""' <<<"$read_only")"
  expected_read_only_if="\${{ steps.fixes.outputs.changed == 'true' && (inputs.apply-signed-fixes != true || github.event_name != 'pull_request' || github.event.pull_request.head.repo.fork == true) }}"
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
      expected_apply_if="\${{ inputs.apply-signed-fixes == true && needs.tidy.outputs.fixes-created == 'true' }}"
      ;;
    apply-golangci-lint-fixes)
      expected_apply_if="\${{ !cancelled() && inputs.apply-signed-fixes == true && needs.golangci-lint.result == 'success' && (needs.apply-tidy-fixes.result == 'success' || needs.apply-tidy-fixes.result == 'skipped') && needs.golangci-lint.outputs.fixes-created == 'true' }}"
      ;;
    apply-fixes)
      expected_apply_if="\${{ !cancelled() && inputs.apply-signed-fixes == true && needs.lint.result == 'success' && (needs.apply-golangci-lint-fixes.result == 'success' || needs.apply-golangci-lint-fixes.result == 'skipped') && needs.lint.outputs.fixes-created == 'true' }}"
      ;;
  esac
  [[ "$apply_if" == "$expected_apply_if" ]] ||
    fail "${apply_job} must use the audited opt-in and predecessor-result gate"
done

echo "PASS: validate-go signed fixes are opt-in, collision-free, strict when read-only, and fail-closed in sequence"
