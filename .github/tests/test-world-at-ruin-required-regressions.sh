#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${repo_root}/.github/workflows/world-at-ruin-required-regressions.yaml"
resolver="${repo_root}/.github/scripts/resolve-world-at-ruin-regression-base.sh"
readme="${repo_root}/README.md"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

failures=0

fail() {
	printf 'world-at-ruin required regressions: FAIL -- %s\n' "$1" >&2
	failures=$((failures + 1))
}

assert_output() {
	local label="$1"
	local expected="$2"
	local actual
	actual="$(cat "${tmp_dir}/output")"
	if [ "${actual}" != "${expected}" ]; then
		fail "${label}: expected output '${expected//$'\n'/, }', got '${actual//$'\n'/, }'"
	fi
}

resolve() {
	local repository="$1"
	local event_name="$2"
	local pull_request_base_sha="$3"
	local merge_group_base_sha="$4"
	: >"${tmp_dir}/output"
	GITHUB_OUTPUT="${tmp_dir}/output" \
		TARGET_REPOSITORY="${repository}" \
		EVENT_NAME="${event_name}" \
		PULL_REQUEST_BASE_SHA="${pull_request_base_sha}" \
		MERGE_GROUP_BASE_SHA="${merge_group_base_sha}" \
		bash "${resolver}"
}

if [ ! -x "${resolver}" ]; then
	fail "trusted-base resolver is missing or non-executable"
else
	pull_request_sha="1111111111111111111111111111111111111111"
	merge_group_sha="2222222222222222222222222222222222222222"

	if resolve "devantler-tech/actions" "pull_request" "${pull_request_sha}" ""; then
		assert_output "source-repository no-op" "run=false"
	else
		fail "the source repository did not complete as a deliberate no-op"
	fi

	if resolve "devantler-tech/world-at-ruin" "pull_request" "${pull_request_sha}" ""; then
		assert_output "pull-request base" $'run=true\ntrusted-sha=1111111111111111111111111111111111111111'
	else
		fail "a valid pull_request event was rejected"
	fi

	if resolve "devantler-tech/world-at-ruin" "merge_group" "" "${merge_group_sha}"; then
		assert_output "merge-group base" $'run=true\ntrusted-sha=2222222222222222222222222222222222222222'
	else
		fail "a valid merge_group event was rejected"
	fi

	if resolve "devantler-tech/platform" "pull_request" "${pull_request_sha}" "" \
		>"${tmp_dir}/wrong-target.log" 2>&1; then
		fail "an unexpected target repository was accepted"
	elif ! grep -q 'unexpected required-workflow target' "${tmp_dir}/wrong-target.log"; then
		fail "wrong-target refusal was not explicit"
	fi

	if resolve "devantler-tech/world-at-ruin" "push" "${pull_request_sha}" "${merge_group_sha}" \
		>"${tmp_dir}/wrong-event.log" 2>&1; then
		fail "an unsupported event was accepted"
	elif ! grep -q 'unsupported required-workflow event' "${tmp_dir}/wrong-event.log"; then
		fail "unsupported-event refusal was not explicit"
	fi

	if resolve "devantler-tech/world-at-ruin" "pull_request" "candidate-controlled-ref" "" \
		>"${tmp_dir}/malformed.log" 2>&1; then
		fail "a malformed trusted base SHA was accepted"
	elif ! grep -q 'trusted base is not a full commit SHA' "${tmp_dir}/malformed.log"; then
		fail "malformed-base refusal was not explicit"
	fi

	if resolve "devantler-tech/world-at-ruin" "merge_group" "" "" \
		>"${tmp_dir}/missing.log" 2>&1; then
		fail "a missing merge-group base SHA was accepted"
	elif ! grep -q 'trusted base is not a full commit SHA' "${tmp_dir}/missing.log"; then
		fail "missing-base refusal was not explicit"
	fi
fi

if [ ! -f "${workflow}" ]; then
	fail "required-workflow source is missing"
else
	if [ "$(yq -r '.permissions | length == 0' "${workflow}")" != "true" ]; then
		fail "workflow-level permissions are not deny-by-default"
	fi
	if [ "$(yq -r '.on | (has("pull_request") and has("merge_group"))' "${workflow}")" != "true" ]; then
		fail "workflow does not expose both required-workflow event triggers"
	fi
	if [ "$(yq -r '.on | has("workflow_call")' "${workflow}")" != "false" ]; then
		fail "target-specific required workflow is incorrectly exposed as a reusable workflow"
	fi
	if [ "$(yq -r '.jobs.eligibility.steps[0].uses' "${workflow}")" != \
		"step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920" ]; then
		fail "Harden Runner is not the first eligibility step at the reviewed pin"
	fi
	if [ "$(yq -r '.jobs.eligibility.timeout-minutes' "${workflow}")" != "5" ]; then
		fail "trusted-base resolution does not fail closed within five minutes"
	fi
	if [ "$(yq -r '.jobs.eligibility.outputs.trusted-sha' "${workflow}")" != \
		'${{ steps.resolve.outputs.trusted-sha }}' ]; then
		fail "trusted base output is not owned by the source-controlled resolver"
	fi
	if [ "$(yq -r '.jobs.trusted-client-regressions.needs' "${workflow}")" != "eligibility" ]; then
		fail "regression job is not gated by trusted event resolution"
	fi
	if [ "$(yq -r '.jobs.trusted-client-regressions.if' "${workflow}")" != \
		"needs.eligibility.outputs.run == 'true'" ]; then
		fail "regression job does not distinguish the source-repository no-op"
	fi
	source_checkout="$(
		yq -o=json -I=0 \
			'.jobs.eligibility.steps[]
			 | select(.name == "📥 Check out the exact ruleset workflow source")
			 | .with | {"repository": .repository, "ref": .ref, "path": .path}' "${workflow}"
	)"
	if [ "${source_checkout}" != \
		'{"repository":"devantler-tech/actions","ref":"${{ github.workflow_sha }}","path":"trusted-workflow-source"}' ]; then
		fail "resolver checkout tuple is not bound to the exact ruleset workflow revision"
	fi

	candidate_checkout="$(
		yq -o=json -I=0 \
			'.jobs.trusted-client-regressions.steps[]
			 | select(.name == "📥 Check out candidate product bytes")
			 | .with | {"repository": .repository, "ref": .ref, "path": .path}' "${workflow}"
	)"
	if [ "${candidate_checkout}" != \
		'{"repository":"${{ github.repository }}","ref":"${{ github.sha }}","path":"candidate"}' ]; then
		fail "candidate checkout tuple is not bound to candidate event bytes"
	fi

	trusted_checkout="$(
		yq -o=json -I=0 \
			'.jobs.trusted-client-regressions.steps[]
			 | select(.name == "📥 Check out trusted base tests and controller")
			 | .with | {"repository": .repository, "ref": .ref, "path": .path}' "${workflow}"
	)"
	if [ "${trusted_checkout}" != \
		'{"repository":"${{ github.repository }}","ref":"${{ needs.eligibility.outputs.trusted-sha }}","path":"trusted"}' ]; then
		fail "trusted checkout tuple is not bound to GitHub-supplied base bytes"
	fi

	install_step="$(
		yq -r \
			'.jobs.trusted-client-regressions.steps[]
			 | select(.name == "🎮 Install Godot (pinned, checksum-verified)")
			 | .run' "${workflow}"
	)"
	if ! grep -qF -- '--retry 4 --retry-delay 2 --retry-all-errors' <<<"${install_step}"; then
		fail "Godot download does not retry bounded transient failures"
	fi
	if ! grep -qF 'trusted/tools/required-regression-control.sh trusted candidate' "${workflow}"; then
		fail "trusted base controller is not the aggregate entrypoint"
	fi
fi

if ! grep -Fq 'refs/heads/main' "${readme}" ||
	! grep -Fq 'provider-upjet-github v0.19.1' "${readme}" ||
	! grep -Fq 'Keep the source workflow active' "${readme}"; then
	fail "README does not describe the live declarative source-ref contract"
fi

for source in "${workflow}" "${resolver}" "${readme}"; do
	if grep -Eq 'pins? (an |the )?exact reviewed commit|disable this workflow|until/if the workflow is disabled' "${source}"; then
		fail "$(basename "${source}") still describes the abandoned exact-pin or disable rollout"
	fi
done

if [ "${failures}" -ne 0 ]; then
	printf 'world-at-ruin required regressions: %d failure(s)\n' "${failures}" >&2
	exit 1
fi

printf '%s\n' \
	'TEST PASS -- World at Ruin required regressions separate candidate and trusted base control'
