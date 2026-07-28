#!/usr/bin/env bash

set -euo pipefail

workflow="${1:-.github/workflows/enable-auto-merge.yaml}"
fixtures="${2:-.github/tests/enable-auto-merge-authors.json}"
ci_workflow="${3:-.github/workflows/ci.yaml}"
condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "classify")
   | .if // ""]
  | join("\n")' "$workflow")"

status=0

actor_gate_default="$(yq -r '.on.workflow_call.inputs."enforce-actor-trust".default | tostring' "$workflow")"
if [[ "$actor_gate_default" != "false" ]]; then
  echo "::error file=$workflow::actor-trust enforcement must ship as a default-off workflow_call input"
  status=1
fi

enabled_test_uses="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".uses // ""' "$ci_workflow")"
enabled_test_flag="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".with."enforce-actor-trust" | tostring' "$ci_workflow")"
enabled_test_permissions="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".permissions | to_entries | sort_by(.key) | map(.key + ":" + .value) | join(",")' "$ci_workflow")"
if [[ "$enabled_test_uses" != "./.github/workflows/enable-auto-merge.yaml" ||
  "$enabled_test_flag" != "true" ||
  "$enabled_test_permissions" != "contents:write,pull-requests:write" ]]; then
  echo "::error file=$ci_workflow::CI must invoke the reusable workflow with actor trust enabled and its exact revoke permissions"
  status=1
fi

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
allowlist_json="$(yq -r '.jobs.eligibility.env.TRUSTED_BOT_AUTHORS' "$workflow" | jq -c .)"
trigger_actors_json="$(yq -r '.jobs.eligibility.env.TRUSTED_TRIGGER_ACTORS' "$workflow" | jq -c .)"
expected_allowlist_json='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]"]'
expected_trigger_actors_json='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","devantler"]'
if [[ "$allowlist_json" != "$expected_allowlist_json" ||
  "$trigger_actors_json" != "$expected_trigger_actors_json" ]]; then
  echo "::error file=$workflow::trusted bot authors and triggering actors must be defined once in the eligibility job"
  status=1
fi
reviewers_json='["coderabbitai[bot]","chatgpt-codex-connector[bot]"]'
normalized_condition="$(tr -d '[:space:]' <<<"$condition")"
expected_condition="\${{(github.event_name=='pull_request'&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login)&&(env.ACTOR_TRUST_ENFORCED!='true'||contains(fromJSON(env.TRUSTED_TRIGGER_ACTORS),github.actor)))||(github.event_name=='pull_request_review'&&contains(fromJSON('$reviewers_json'),github.event.review.user.login)&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login))||(github.event_name=='issue_comment'&&github.event.issue.pull_request&&github.event.issue.state=='open'&&contains(fromJSON('$reviewers_json'),github.event.comment.user.login)&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.issue.user.login))}}"
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
expected_disarm_condition="\${{env.ACTOR_TRUST_ENFORCED=='true'&&github.event_name=='pull_request'&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login)&&!contains(fromJSON(env.TRUSTED_TRIGGER_ACTORS),github.actor)}}"
if [[ "$normalized_disarm_condition" != "$expected_disarm_condition" ]]; then
  echo "::error file=$workflow::rejected trusted-author pull_request events must be classified for fail-closed disarm"
  echo "expected: $expected_disarm_condition"
  echo "actual:   $normalized_disarm_condition"
  status=1
fi

disarm_job_condition="$(yq -r '.jobs."disarm-untrusted-update".if // ""' "$workflow")"
if [[ "$disarm_job_condition" != "needs.eligibility.outputs.disarm == 'true'" ]]; then
  echo "::error file=$workflow::the disarm job must run only for exactly-true rejected pull_request events"
  status=1
fi

disarm_job_permissions="$(yq -r '.jobs."disarm-untrusted-update".permissions | to_entries | sort_by(.key) | map(.key + ":" + .value) | join(",")' "$workflow")"
if [[ "$disarm_job_permissions" != "contents:write,pull-requests:write" ]]; then
  echo "::error file=$workflow::the rejected-update disarm path must grant only the two write scopes required to revoke auto-merge"
  status=1
fi

disarm_job="$(yq -r '.jobs."disarm-untrusted-update" // {}' "$workflow")"
if grep -Fq 'APP_PRIVATE_KEY' <<<"$disarm_job" ||
  grep -Fq 'create-github-app-token' <<<"$disarm_job"; then
  echo "::error file=$workflow::rejected updates must disarm with GITHUB_TOKEN and never receive the App private key"
  status=1
fi
disarm_concurrency_group="$(yq -r '.jobs."disarm-untrusted-update".concurrency.group // ""' "$workflow")"
disarm_cancel_in_progress="$(yq -r '.jobs."disarm-untrusted-update".concurrency."cancel-in-progress" | tostring' "$workflow")"
auto_merge_concurrency_group="$(yq -r '.jobs."auto-merge".concurrency.group // ""' "$workflow")"
auto_merge_cancel_in_progress="$(yq -r '.jobs."auto-merge".concurrency."cancel-in-progress" // ""' "$workflow")"
expected_auto_merge_cancel="\${{ github.event_name == 'pull_request' && (inputs.enforce-actor-trust || vars.ENFORCE_ACTOR_TRUST == 'true') }}"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
if [[ "$disarm_concurrency_group" != 'enable-auto-merge-actor-${{ github.event.pull_request.number }}' ||
  "$disarm_cancel_in_progress" != "true" ||
  "$auto_merge_concurrency_group" != "enable-auto-merge-\${{ github.event_name == 'pull_request' && 'actor' || 'review' }}-\${{ github.event.pull_request.number || github.event.issue.number || github.run_id }}" ||
  "$auto_merge_cancel_in_progress" != "$expected_auto_merge_cancel" ]]; then
  echo "::error file=$workflow::pull_request arming and rejection must share a newest-event-wins actor concurrency group"
  status=1
fi
disarm_checkout_uses="$(yq -r '
  [.jobs."disarm-untrusted-update".steps[]
   | select(.name == "📥 Checkout trusted disarm script")
   | .uses // ""]
  | join("\n")' "$workflow")"
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
if [[ "$disarm_checkout_uses" != "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1" ||
  "$disarm_checkout_repository" != '${{ job.workflow_repository }}' ||
  "$disarm_checkout_ref" != '${{ github.event.repository.full_name == job.workflow_repository && github.event.pull_request.base.sha || job.workflow_sha }}' ||
  "$disarm_checkout_persist" != "false" ]]; then
  echo "::error file=$workflow::rejected updates must run the disarm script from the trusted base/called-workflow commit without persisted credentials"
  status=1
fi
if ! grep -Fq 'disarm-auto-merge.sh' <<<"$disarm_job"; then
  echo "::error file=$workflow::rejected updates must revoke both classic auto-merge and merge-queue state"
  status=1
fi

resolve_env="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🔎 Resolve target pull request")
   | .env // {}][0]' "$workflow")"
resolve_run="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🔎 Resolve target pull request")
   | .run // ""]
  | join("\n")' "$workflow")"
expected_enforce_expr="\${{ (inputs.enforce-actor-trust || vars.ENFORCE_ACTOR_TRUST == 'true') && 'true' || 'false' }}"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
if [[ "$(yq -r '.EVENT_HEAD // ""' <<<"$resolve_env")" != '${{ github.event.pull_request.head.sha }}' ||
  "$(yq -r '.EVENT_UPDATED_AT // ""' <<<"$resolve_env")" != '${{ github.event.pull_request.updated_at }}' ||
  "$(yq -r '.ENFORCE_ACTOR_TRUST // ""' <<<"$resolve_env")" != "$expected_enforce_expr" ||
  "$resolve_run" != *"headRefOid"* ||
  "$resolve_run" != *"updatedAt"* ||
  "$resolve_run" != *'echo "head_sha=$HEAD_SHA" >> "$GITHUB_OUTPUT"'* ||
  "$resolve_run" != *'[[ "$ENFORCE_ACTOR_TRUST" == "true" && "$EVENT_NAME" == "pull_request" && ( "$HEAD_SHA" != "$EVENT_HEAD" || "$LIVE_UPDATED_AT" != "$EVENT_UPDATED_AT" ) ]]'* ]]; then
  echo "::error file=$workflow::actor enforcement must reject pull_request runs superseded by a newer head or lifecycle event"
  status=1
fi

gates_head_env="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🛂 Verify review and pre-merge gates")
   | .env.HEAD_SHA // ""]
  | join("\n")' "$workflow")"
# shellcheck disable=SC2016 # GitHub expression is compared literally.
if [[ "$gates_head_env" != '${{ steps.pr.outputs.head_sha }}' ]]; then
  echo "::error file=$workflow::the gate must carry the event-bound head through approval and arming"
  status=1
fi

while IFS= read -r fixture; do
  name="$(jq -r '.name' <<<"$fixture")"
  event_name="$(jq -r '.event_name' <<<"$fixture")"
  draft="$(jq -r '.draft' <<<"$fixture")"
  login="$(jq -r '.login' <<<"$fixture")"
  actor="$(jq -r '.actor' <<<"$fixture")"
  enforce="$(jq -r 'if has("enforce") then .enforce else true end' <<<"$fixture")"
  expected="$(jq -r '.eligible' <<<"$fixture")"
  expected_disarm="$(jq -r '.disarm // false' <<<"$fixture")"
  actual=false
  actual_disarm=false

  if [[ "$event_name" == "pull_request" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    { [[ "$enforce" != "true" ]] ||
      jq -e --arg actor "$actor" 'index($actor) != null' <<<"$trigger_actors_json" >/dev/null; }; then
    actual=true
  fi

  if [[ "$enforce" == "true" && "$event_name" == "pull_request" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    ! jq -e --arg actor "$actor" 'index($actor) != null' <<<"$trigger_actors_json" >/dev/null; then
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
