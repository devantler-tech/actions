#!/usr/bin/env bash

set -euo pipefail

workflow="${1:-.github/workflows/enable-auto-merge.yaml}"
fixtures="${2:-.github/tests/enable-auto-merge-authors.json}"
condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "classify")
   | .if // ""]
  | join("\n")' "$workflow")"

status=0

# A required workflow must complete successfully for ineligible events rather
# than making its only job SKIPPED. Keep classification in an unconditional,
# zero-permission job and gate the privileged job on its output.
eligibility_job_condition="$(yq -r '.jobs.eligibility.if // ""' "$workflow")"
if [[ -n "$eligibility_job_condition" ]]; then
  echo "::error file=$workflow::eligibility job must be unconditional so required workflows complete for ineligible events"
  status=1
fi

eligibility_permissions="$(yq -r '(.jobs.eligibility.permissions // {}) | keys | join(",")' "$workflow")"
if [[ -n "$eligibility_permissions" ]]; then
  echo "::error file=$workflow::eligibility job must not request repository permissions; got: $eligibility_permissions"
  status=1
fi

eligibility_first_uses="$(yq -r '.jobs.eligibility.steps[0].uses // ""' "$workflow")"
eligibility_first_egress="$(yq -r '.jobs.eligibility.steps[0].with."egress-policy" // ""' "$workflow")"
if [[ "$eligibility_first_uses" != "step-security/harden-runner@bf7454d06d71f1098171f2acdf0cd4708d7b5920" ||
  "$eligibility_first_egress" != "audit" ]]; then
  echo "::error file=$workflow::eligibility must begin with the pinned harden-runner action in audit mode"
  status=1
fi

eligibility_output="$(yq -r '.jobs.eligibility.outputs.eligible // ""' "$workflow")"
# shellcheck disable=SC2016 # GitHub expression is intentionally compared literally.
if [[ "$eligibility_output" != '${{ steps.classify.outputs.eligible }}' ]]; then
  echo "::error file=$workflow::eligibility output must be bound to steps.classify.outputs.eligible"
  status=1
fi

disarm_output="$(yq -r '.jobs.eligibility.outputs.disarm // ""' "$workflow")"
# shellcheck disable=SC2016 # GitHub expression is intentionally compared literally.
if [[ "$disarm_output" != '${{ steps.classify-disarm.outputs.disarm }}' ]]; then
  echo "::error file=$workflow::eligibility output must expose rejected synchronize events for fail-closed disarm"
  status=1
fi

ineligible_condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "ineligible")
   | .if // ""]
  | join("\n")' "$workflow")"
if [[ "$ineligible_condition" != *"steps.classify.outputs.eligible != 'true'"* ]]; then
  echo "::error file=$workflow::eligibility job needs an explicit successful ineligible-event step"
  status=1
fi

auto_merge_needs="$(yq -r '.jobs."auto-merge".needs // ""' "$workflow")"
auto_merge_condition="$(yq -r '.jobs."auto-merge".if // ""' "$workflow")"
if [[ "$auto_merge_needs" != "eligibility" ||
  "$auto_merge_condition" != "needs.eligibility.outputs.eligible == 'true'" ]]; then
  echo "::error file=$workflow::privileged auto-merge job must depend only on an exactly-true eligibility output"
  status=1
fi

eligibility_uses="$(yq -r '[(.jobs.eligibility.steps // [])[] | .uses // ""] | join("\n")' "$workflow")"
if [[ "$eligibility_uses" == *"create-github-app-token"* ]]; then
  echo "::error file=$workflow::ineligible events must not mint a privileged GitHub App token"
  status=1
fi

# Match the complete classifier shape rather than checking that a few strings
# occur somewhere. This proves each allowlist is attached to the correct event
# actor and rejects extra OR branches that could bypass the privileged gate.
allowlist_json='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]"]'
reviewers_json='["coderabbitai[bot]","chatgpt-codex-connector[bot]"]'
normalized_condition="$(tr -d '[:space:]' <<<"$condition")"
expected_condition="\${{(github.event_name=='pull_request'&&!github.event.pull_request.draft&&contains(fromJSON('$allowlist_json'),github.event.pull_request.user.login)&&(github.event.action!='synchronize'||contains(fromJSON('$allowlist_json'),github.actor)))||(github.event_name=='pull_request_review'&&contains(fromJSON('$reviewers_json'),github.event.review.user.login)&&!github.event.pull_request.draft&&contains(fromJSON('$allowlist_json'),github.event.pull_request.user.login))||(github.event_name=='issue_comment'&&github.event.issue.pull_request&&github.event.issue.state=='open'&&contains(fromJSON('$reviewers_json'),github.event.comment.user.login)&&contains(fromJSON('$allowlist_json'),github.event.issue.user.login))}}"
if [[ "$normalized_condition" != "$expected_condition" ]]; then
  echo "::error file=$workflow::eligibility classifier must exactly preserve the pull_request, pull_request_review, and issue_comment trust branches"
  echo "expected: $expected_condition"
  echo "actual:   $normalized_condition"
  status=1
fi

disarm_condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "classify-disarm")
   | .if // ""]
  | join("\n")' "$workflow")"
normalized_disarm_condition="$(tr -d '[:space:]' <<<"$disarm_condition")"
expected_disarm_condition="\${{github.event_name=='pull_request'&&github.event.action=='synchronize'&&!github.event.pull_request.draft&&contains(fromJSON('$allowlist_json'),github.event.pull_request.user.login)&&!contains(fromJSON('$allowlist_json'),github.actor)}}"
if [[ "$normalized_disarm_condition" != "$expected_disarm_condition" ]]; then
  echo "::error file=$workflow::rejected trusted-author synchronize events must be classified for fail-closed disarm"
  echo "expected: $expected_disarm_condition"
  echo "actual:   $normalized_disarm_condition"
  status=1
fi

disarm_job_condition="$(yq -r '.jobs."disarm-untrusted-update".if // ""' "$workflow")"
if [[ "$disarm_job_condition" != "needs.eligibility.outputs.disarm == 'true'" ]]; then
  echo "::error file=$workflow::the disarm job must run only for exactly-true rejected synchronize events"
  status=1
fi

disarm_job_permissions="$(yq -r '.jobs."disarm-untrusted-update".permissions | to_entries | sort_by(.key) | map(.key + ":" + .value) | join(",")' "$workflow")"
if [[ "$disarm_job_permissions" != "contents:read,pull-requests:write" ]]; then
  echo "::error file=$workflow::the rejected-update disarm path must use only contents:read and pull-requests:write"
  status=1
fi

disarm_job="$(yq -r '.jobs."disarm-untrusted-update" // {}' "$workflow")"
if grep -Fq 'APP_PRIVATE_KEY' <<<"$disarm_job" ||
  grep -Fq 'create-github-app-token' <<<"$disarm_job"; then
  echo "::error file=$workflow::rejected updates must disarm with GITHUB_TOKEN and never receive the App private key"
  status=1
fi
disarm_checkout_repository="$(yq -r '
  [.jobs."disarm-untrusted-update".steps[]
   | select(.name == "📥 Checkout trusted disarm script")
   | .with.repository // ""]
  | join("\n")' "$workflow")"
disarm_checkout_ref="$(yq -r '
  [.jobs."disarm-untrusted-update".steps[]
   | select(.name == "📥 Checkout trusted disarm script")
   | .with.ref // ""]
  | join("\n")' "$workflow")"
disarm_checkout_persist="$(yq -r '
  [.jobs."disarm-untrusted-update".steps[]
   | select(.name == "📥 Checkout trusted disarm script")
   | .with."persist-credentials"]
  | join("\n")' "$workflow")"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
if [[ "$disarm_checkout_repository" != '${{ job.workflow_repository }}' ||
  "$disarm_checkout_ref" != '${{ github.event.repository.full_name == job.workflow_repository && github.event.pull_request.base.sha || job.workflow_sha }}' ||
  "$disarm_checkout_persist" != "false" ]]; then
  echo "::error file=$workflow::rejected updates must run the disarm script from the trusted base/called-workflow commit without persisted credentials"
  status=1
fi
if ! grep -Fq 'disarm-auto-merge.sh' <<<"$disarm_job"; then
  echo "::error file=$workflow::rejected updates must revoke both classic auto-merge and merge-queue state"
  status=1
fi

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  event_name="$(jq -r '.event_name' <<<"$fixture")"
  action="$(jq -r '.action // "opened"' <<<"$fixture")"
  draft="$(jq -r '.draft' <<<"$fixture")"
  login="$(jq -r '.login' <<<"$fixture")"
  actor="$(jq -r '.actor' <<<"$fixture")"
  expected="$(jq -r '.eligible' <<<"$fixture")"
  expected_disarm="$(jq -r '.disarm // false' <<<"$fixture")"
  actual=false
  actual_disarm=false

  if [[ "$event_name" == "pull_request" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    { [[ "$action" != "synchronize" ]] ||
      jq -e --arg actor "$actor" 'index($actor) != null' <<<"$allowlist_json" >/dev/null; }; then
    actual=true
  fi

  if [[ "$event_name" == "pull_request" && "$action" == "synchronize" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    ! jq -e --arg actor "$actor" 'index($actor) != null' <<<"$allowlist_json" >/dev/null; then
    actual_disarm=true
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "::error file=$fixtures::fixture '$name' expected eligible=$expected, got $actual"
    status=1
  else
    echo "fixture '$name': eligible=$actual"
  fi
  if [[ "$actual_disarm" != "$expected_disarm" ]]; then
    echo "::error file=$fixtures::fixture '$name' expected disarm=$expected_disarm, got $actual_disarm"
    status=1
  else
    echo "fixture '$name': disarm=$actual_disarm"
  fi
done < <(jq -c '.[]' "$fixtures")

exit "$status"
