#!/usr/bin/env bash

set -euo pipefail

workflow="${1:-.github/workflows/enable-auto-merge.yaml}"
fixtures="${2:-.github/tests/enable-auto-merge-authors.json}"
ci_workflow="${3:-.github/workflows/ci.yaml}"
readme="${4:-README.md}"
condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "classify")
   | .if // ""]
  | join("\n")' "$workflow")"

status=0

actor_gate_default="$(yq -r '.on.workflow_call.inputs."enforce-actor-trust".default | tostring' "$workflow")"
concurrency_key_default="$(yq -r '.on.workflow_call.inputs."concurrency-key".default // ""' "$workflow")"
if [[ "$actor_gate_default" != "false" || -n "$concurrency_key_default" ]]; then
  echo "::error file=$workflow::actor-trust enforcement must ship as a default-off workflow_call input"
  status=1
fi

default_test_key="$(yq -r '.jobs."test-enable-auto-merge".with."concurrency-key" // ""' "$ci_workflow")"
enabled_test_uses="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".uses // ""' "$ci_workflow")"
enabled_test_flag="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".with."enforce-actor-trust" | tostring' "$ci_workflow")"
enabled_test_key="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".with."concurrency-key" // ""' "$ci_workflow")"
enabled_test_permissions="$(yq -r '.jobs."test-enable-auto-merge-actor-trust".permissions | to_entries | sort_by(.key) | map(.key + ":" + .value) | join(",")' "$ci_workflow")"
if [[ "$enabled_test_uses" != "./.github/workflows/enable-auto-merge.yaml" ||
  "$enabled_test_flag" != "true" ||
  "$default_test_key" != "default-self-test" ||
  "$enabled_test_key" != "actor-trust-self-test" ||
  "$enabled_test_permissions" != "actions:read,contents:write,pull-requests:write" ]]; then
  echo "::error file=$ci_workflow::CI must isolate its two reusable invocations and exercise actor trust with exact revoke permissions"
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
if [[ "$eligibility_first_uses" != "step-security/harden-runner@05e31511f85b41b11d1cf0ef85d0992719546e2c" ||
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
configuration_condition="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "legacy-concurrency-key")
   | .if // ""]
  | join("\n")' "$workflow")"
configuration_run="$(yq -r '
  [(.jobs.eligibility.steps // [])[]
   | select(.id == "legacy-concurrency-key")
   | .run // ""]
  | join("\n")' "$workflow")"
expected_configuration_condition="\${{env.ACTOR_TRUST_ENFORCED=='true'&&job.workflow_ref!=github.workflow_ref&&inputs.concurrency-key==''}}"
normalized_configuration_condition="$(tr -d '[:space:]' <<<"$configuration_condition")"
if [[ "$normalized_configuration_condition" != "$expected_configuration_condition" ||
  "$configuration_run" != *"repository-wide compatibility lane"* ||
  "$configuration_run" == *"exit 1"* ]]; then
  echo "::error file=$workflow::actor-enforced legacy callers must retain a safe repository-wide compatibility lane while explicit keys remain isolated"
  status=1
fi

# shellcheck disable=SC2016 # Backticks are literal Markdown in this regex.
if ! grep -Eq '^\| `concurrency-key` +\| Input +\| `""` +\| No +\|.*[Rr]ecommended.*actor trust' "$readme"; then
  echo "::error file=$readme::the public inputs table must document concurrency-key and its actor-trust compatibility contract"
  status=1
fi

auto_merge_needs="$(yq -r '.jobs."auto-merge".needs // ""' "$workflow")"
auto_merge_condition="$(yq -r '.jobs."auto-merge".if // ""' "$workflow")"
normalized_auto_merge_condition="$(tr -d '[:space:]' <<<"$auto_merge_condition")"
expected_auto_merge_condition="needs.eligibility.outputs.eligible=='true'&&(github.event_name=='pull_request'||inputs.enforce-review-gates||vars.ENFORCE_MERGE_GATES=='true')"
if [[ "$auto_merge_needs" != "eligibility" ||
  "$normalized_auto_merge_condition" != "$expected_auto_merge_condition" ]]; then
  echo "::error file=$workflow::privileged auto-merge job must require exact eligibility and keep default-off review/comment no-ops outside the mutation lane"
  status=1
fi

workflow_text="$(yq -r '.' "$workflow")"
app_token_condition="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.id == "app-token")
   | .if // ""][0]' "$workflow")"
app_token_base_condition="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.id == "app-token-base")
   | .if // ""][0]' "$workflow")"
write_checkout_condition="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "📥 Checkout devantler-tech/actions (this workflow'\''s commit)")
   | .if // ""][0]' "$workflow")"
resolve_condition="$(yq -r '
  [.jobs."auto-merge".steps[]
   | select(.name == "🔎 Resolve target pull request")
   | .if // ""][0]' "$workflow")"
if [[ "$workflow_text" == *"event-order-token"* ||
  "$workflow_text" == *"is-current-pull-request-workflow-run.sh"* ||
  -n "$app_token_condition" ||
  "$app_token_base_condition" != "steps.app-token.outcome == 'failure'" ||
  -n "$write_checkout_condition" ||
  -n "$resolve_condition" ]]; then
  echo "::error file=$workflow::caller-keyed workflow concurrency must be the sole lifecycle arbiter; surrounding caller-run history must not suppress this lane"
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
allowlist_json="$(yq -r '.env.TRUSTED_BOT_AUTHORS' "$workflow" | jq -c .)"
trigger_actors_json="$(yq -r '.env.TRUSTED_TRIGGER_ACTORS' "$workflow" | jq -c .)"
expected_allowlist_json='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","cursor[bot]"]'
expected_trigger_actors_json='["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","cursor[bot]","chatgpt-codex-connector[bot]","devantler"]'
if [[ "$allowlist_json" != "$expected_allowlist_json" ||
  "$trigger_actors_json" != "$expected_trigger_actors_json" ]]; then
  echo "::error file=$workflow::trusted bot authors and triggering actors must be defined once in the eligibility job"
  status=1
fi
reviewers_json="$(yq -r '.env.TRUSTED_REVIEW_ACTORS' "$workflow" | jq -c .)"
expected_reviewers_json='["coderabbitai[bot]","chatgpt-codex-connector[bot]"]'
if [[ "$reviewers_json" != "$expected_reviewers_json" ]]; then
  echo "::error file=$workflow::trusted review and comment actors must be defined once in the workflow environment"
  status=1
fi
normalized_condition="$(tr -d '[:space:]' <<<"$condition")"
expected_condition="\${{((github.event_name=='pull_request'&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login))||(github.event_name=='pull_request_review'&&contains(fromJSON(env.TRUSTED_REVIEW_ACTORS),github.event.review.user.login)&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login))||(github.event_name=='issue_comment'&&github.event.issue.pull_request&&github.event.issue.state=='open'&&contains(fromJSON(env.TRUSTED_REVIEW_ACTORS),github.event.comment.user.login)&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.issue.user.login)))&&(env.ACTOR_TRUST_ENFORCED!='true'||(contains(fromJSON(env.TRUSTED_TRIGGER_ACTORS),github.actor)&&contains(fromJSON(env.TRUSTED_TRIGGER_ACTORS),github.triggering_actor)))}}"
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
expected_disarm_condition="\${{env.ACTOR_TRUST_ENFORCED=='true'&&((github.event_name=='pull_request'&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login))||((inputs.enforce-review-gates||vars.ENFORCE_MERGE_GATES=='true')&&((github.event_name=='pull_request_review'&&github.event.action=='dismissed'&&contains(fromJSON(env.TRUSTED_REVIEW_ACTORS),github.event.review.user.login)&&!github.event.pull_request.draft&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.pull_request.user.login))||(github.event_name=='issue_comment'&&github.event.action=='deleted'&&github.event.issue.pull_request&&github.event.issue.state=='open'&&contains(fromJSON(env.TRUSTED_REVIEW_ACTORS),github.event.comment.user.login)&&contains(fromJSON(env.TRUSTED_BOT_AUTHORS),github.event.issue.user.login)))))&&(!contains(fromJSON(env.TRUSTED_TRIGGER_ACTORS),github.actor)||!contains(fromJSON(env.TRUSTED_TRIGGER_ACTORS),github.triggering_actor))}}"
if [[ "$normalized_disarm_condition" != "$expected_disarm_condition" ]]; then
  echo "::error file=$workflow::rejected trusted-author lifecycle and evidence-removal events must be classified for fail-closed disarm"
  echo "expected: $expected_disarm_condition"
  echo "actual:   $normalized_disarm_condition"
  status=1
fi

disarm_job_condition="$(yq -r '.jobs."disarm-untrusted-update".if // ""' "$workflow")"
if [[ "$disarm_job_condition" != "needs.eligibility.outputs.disarm == 'true'" ]]; then
  echo "::error file=$workflow::the disarm job must run only for exactly-true rejected lifecycle or evidence-removal events"
  status=1
fi

disarm_job_permissions="$(yq -r '.jobs."disarm-untrusted-update".permissions | to_entries | sort_by(.key) | map(.key + ":" + .value) | join(",")' "$workflow")"
if [[ "$disarm_job_permissions" != "actions:read,contents:write,pull-requests:write" ]]; then
  echo "::error file=$workflow::the rejected-update disarm path must grant only run-time lookup plus revocation writes"
  status=1
fi

disarm_job="$(yq -r '.jobs."disarm-untrusted-update" // {}' "$workflow")"
if grep -Fq 'APP_PRIVATE_KEY' <<<"$disarm_job" ||
  grep -Fq 'create-github-app-token' <<<"$disarm_job"; then
  echo "::error file=$workflow::rejected updates must disarm with GITHUB_TOKEN and never receive the App private key"
  status=1
fi
workflow_concurrency_group="$(yq -r '.concurrency.group // ""' "$workflow")"
workflow_cancel_in_progress="$(yq -r '.concurrency."cancel-in-progress" // ""' "$workflow")"
workflow_queue="$(yq -r '.concurrency.queue // "single"' "$workflow")"
expected_workflow_cancel="\${{ (inputs.enforce-actor-trust || vars.ENFORCE_ACTOR_TRUST == 'true') && (github.event_name == 'pull_request' || ((inputs.enforce-review-gates || vars.ENFORCE_MERGE_GATES == 'true') && (github.event.action == 'dismissed' || github.event.action == 'deleted'))) }}"
# The queue chooses single only for the same events that intentionally cancel
# stale workflow runs. Every non-cancelling run retains its pending evaluation.
cancel_condition="${expected_workflow_cancel#\$\{\{ }"
cancel_condition="${cancel_condition% \}\}}"
expected_workflow_queue="\${{ ($cancel_condition) && 'single' || 'max' }}"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
expected_workflow_group='enable-auto-merge-${{github.repository}}-${{inputs.concurrency-key||(startsWith(github.workflow_ref,'"'"'devantler-tech/actions/.github/workflows/enable-auto-merge.yaml@'"'"')&&'"'"'direct'"'"')||((inputs.enforce-actor-trust||vars.ENFORCE_ACTOR_TRUST=='"'"'true'"'"')&&'"'"'actor-trust-legacy'"'"')||github.workflow_ref}}-${{github.event.pull_request.number||github.event.issue.number||github.run_id}}-${{((inputs.concurrency-key!='"'"''"'"'||startsWith(github.workflow_ref,'"'"'devantler-tech/actions/.github/workflows/enable-auto-merge.yaml@'"'"')||inputs.enforce-actor-trust||vars.ENFORCE_ACTOR_TRUST=='"'"'true'"'"')&&((github.event_name=='"'"'pull_request'"'"'&&!github.event.pull_request.draft&&contains(fromJSON('"'"'["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","cursor[bot]"]'"'"'),github.event.pull_request.user.login))||((inputs.enforce-review-gates||vars.ENFORCE_MERGE_GATES=='"'"'true'"'"')&&((github.event_name=='"'"'pull_request_review'"'"'&&github.event.action=='"'"'dismissed'"'"'&&!github.event.pull_request.draft&&contains(fromJSON('"'"'["coderabbitai[bot]","chatgpt-codex-connector[bot]"]'"'"'),github.event.review.user.login)&&contains(fromJSON('"'"'["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","cursor[bot]"]'"'"'),github.event.pull_request.user.login))||(github.event_name=='"'"'issue_comment'"'"'&&github.event.action=='"'"'deleted'"'"'&&github.event.issue.pull_request&&github.event.issue.state=='"'"'open'"'"'&&contains(fromJSON('"'"'["coderabbitai[bot]","chatgpt-codex-connector[bot]"]'"'"'),github.event.comment.user.login)&&contains(fromJSON('"'"'["dependabot[bot]","renovate[bot]","github-actions[bot]","ksail-bot[bot]","coderabbitai[bot]","cursor[bot]"]'"'"'),github.event.issue.user.login))))))&&'"'"'state'"'"'||github.run_id}}'
normalized_workflow_group="$(tr -d '[:space:]' <<<"$workflow_concurrency_group")"
review_job_group="$(yq -r '.jobs."auto-merge".concurrency.group // ""' "$workflow")"
review_job_cancel="$(yq -r '.jobs."auto-merge".concurrency."cancel-in-progress" | tostring' "$workflow")"
review_job_queue="$(yq -r '.jobs."auto-merge".concurrency.queue // "single"' "$workflow")"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
expected_review_job_group='enable-auto-merge-mutation-${{ github.repository }}-${{ inputs.concurrency-key || (startsWith(github.workflow_ref, '"'"'devantler-tech/actions/.github/workflows/enable-auto-merge.yaml@'"'"') && '"'"'direct'"'"') || ((inputs.enforce-actor-trust || vars.ENFORCE_ACTOR_TRUST == '"'"'true'"'"') && '"'"'actor-trust-legacy'"'"') || github.workflow_ref }}-${{ github.event.pull_request.number || github.event.issue.number || github.run_id }}'
disarm_job_group="$(yq -r '.jobs."disarm-untrusted-update".concurrency.group // ""' "$workflow")"
disarm_job_cancel="$(yq -r '.jobs."disarm-untrusted-update".concurrency."cancel-in-progress" | tostring' "$workflow")"
disarm_job_queue="$(yq -r '.jobs."disarm-untrusted-update".concurrency.queue // "single"' "$workflow")"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
if [[ "$normalized_workflow_group" != "$expected_workflow_group" ||
  "$workflow_cancel_in_progress" != "$expected_workflow_cancel" ||
  "$review_job_group" != "$expected_review_job_group" ||
  "$review_job_cancel" != "false" ||
  "$disarm_job_group" != "$expected_review_job_group" ||
  "$disarm_job_cancel" != "false" ]]; then
  echo "::error file=$workflow::lifecycle and evidence-removal runs must arbitrate at workflow creation before any privileged job can mutate the PR"
  status=1
fi
if [[ "$workflow_queue" != "$expected_workflow_queue" ||
  "$review_job_queue" != "max" || "$disarm_job_queue" != "max" ]]; then
  echo "::error file=$workflow::non-cancelling workflow runs and both mutation jobs must retain pending evaluations; cancelling runs must use the single queue"
  status=1
fi
queue_fixture="$(yq -o=json '.jobs."test-enable-auto-merge-queue"' "$ci_workflow")"
if ! jq -e --arg queue "$review_job_queue" '
  .concurrency.queue == $queue and .concurrency["cancel-in-progress"] == false
  and .permissions == {} and .strategy["fail-fast"] == false
  and .strategy["max-parallel"] == 3 and .strategy.matrix.slot == [1, 2, 3]
' <<<"$queue_fixture" >/dev/null; then
  echo "::error file=$ci_workflow::CI must exercise the production mutation queue with three concurrent, unprivileged slots"
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
if ! grep -Fq 'disarm-auto-merge.sh' <<<"$disarm_job" ||
  grep -Fq 'disarm-untrusted-event.sh' <<<"$disarm_job"; then
  echo "::error file=$workflow::workflow-serialized rejected updates must invoke only the shared revocation helper"
  status=1
fi

disarm_step_env="$(yq -r '
  [.jobs."disarm-untrusted-update".steps[]
   | select(.name == "🔒 Disarm auto-merge after rejected event")
   | .env // {}][0]' "$workflow")"
disarm_step_run="$(yq -r '
  [.jobs."disarm-untrusted-update".steps[]
   | select(.name == "🔒 Disarm auto-merge after rejected event")
   | .run // ""]
  | join("\n")' "$workflow")"
# shellcheck disable=SC2016 # GitHub expressions are compared literally.
if [[ "$(yq -r '.PR_NUMBER // ""' <<<"$disarm_step_env")" != '${{ github.event.pull_request.number || github.event.issue.number }}' ||
  "$(yq -r '.RUN_ID // ""' <<<"$disarm_step_env")" != '${{ github.run_id }}' ||
  "$(yq -r '.RUN_ATTEMPT // ""' <<<"$disarm_step_env")" != '${{ github.run_attempt }}' ||
  "$disarm_step_run" != *"disarm-auto-merge.sh"* ||
  "$disarm_step_run" != *'actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT'* ||
  "$disarm_step_run" != *".run_started_at"* ||
  "$disarm_step_run" != *'"$REPOSITORY" "$PR_NUMBER" "$attempt_started_at"'* ]]; then
  echo "::error file=$workflow::rejected events must pass their durable current-attempt start time and target PR to the serialized revocation helper"
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
  "$(yq -r '.EVENT_ACTION // ""' <<<"$resolve_env")" != '${{ github.event.action }}' ||
  "$(yq -r '.EVENT_BEFORE // ""' <<<"$resolve_env")" != '${{ github.event.before }}' ||
  "$(yq -r '.EVENT_UPDATED_AT // ""' <<<"$resolve_env")" != '${{ github.event.pull_request.updated_at }}' ||
  "$(yq -r '.ENFORCE_ACTOR_TRUST // ""' <<<"$resolve_env")" != "$expected_enforce_expr" ||
  "$resolve_run" != *"headRefOid"* ||
  "$resolve_run" != *"timelineItems(first:100,after:\$endCursor,itemTypes:[REOPENED_EVENT,READY_FOR_REVIEW_EVENT,HEAD_REF_FORCE_PUSHED_EVENT])"* ||
  "$resolve_run" != *"... on HeadRefForcePushedEvent{createdAt beforeCommit{oid} afterCommit{oid}}"* ||
  "$resolve_run" != *"pageInfo{hasNextPage endCursor}"* ||
  "$resolve_run" != *"is-current-pull-request-lifecycle.sh"* ||
  "$resolve_run" != *'"$EVENT_ACTION" "$EVENT_UPDATED_AT" "$EVENT_BEFORE" "$EVENT_HEAD"'* ||
  "$resolve_run" != *'echo "head_sha=$HEAD_SHA" >> "$GITHUB_OUTPUT"'* ||
  "$resolve_run" != *'[[ "$ENFORCE_ACTOR_TRUST" == "true" && "$EVENT_NAME" == "pull_request" && "$HEAD_SHA" != "$EVENT_HEAD" ]]'* ]]; then
  echo "::error file=$workflow::actor enforcement must reject a moved head or a later same-head lifecycle event without treating unrelated PR edits as supersession"
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
  action="$(jq -r '.action // ""' <<<"$fixture")"
  draft="$(jq -r '.draft' <<<"$fixture")"
  login="$(jq -r '.login' <<<"$fixture")"
  actor="$(jq -r '.actor' <<<"$fixture")"
  triggering_actor="$(jq -r '.triggering_actor // .actor' <<<"$fixture")"
  reviewer="$(jq -r '.reviewer // ""' <<<"$fixture")"
  issue_open="$(jq -r '.issue_open // true' <<<"$fixture")"
  has_pull_request="$(jq -r '.has_pull_request // true' <<<"$fixture")"
  enforce="$(jq -r 'if has("enforce") then .enforce else true end' <<<"$fixture")"
  review_enforce="$(jq -r '.review_enforce // false' <<<"$fixture")"
  expected="$(jq -r '.eligible' <<<"$fixture")"
  expected_disarm="$(jq -r '.disarm // false' <<<"$fixture")"
  actual=false
  actual_disarm=false

  base_eligible=false
  if [[ "$event_name" == "pull_request" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null; then
    base_eligible=true
  elif [[ "$event_name" == "pull_request_review" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    jq -e --arg reviewer "$reviewer" 'index($reviewer) != null' <<<"$reviewers_json" >/dev/null; then
    base_eligible=true
  elif [[ "$event_name" == "issue_comment" && "$issue_open" == "true" && "$has_pull_request" == "true" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    jq -e --arg reviewer "$reviewer" 'index($reviewer) != null' <<<"$reviewers_json" >/dev/null; then
    base_eligible=true
  fi

  if [[ "$base_eligible" == "true" ]] &&
    { [[ "$enforce" != "true" ]] ||
      { jq -e --arg actor "$actor" 'index($actor) != null' <<<"$trigger_actors_json" >/dev/null &&
        jq -e --arg actor "$triggering_actor" 'index($actor) != null' <<<"$trigger_actors_json" >/dev/null; }; }; then
    actual=true
  fi

  base_disarm=false
  if [[ "$event_name" == "pull_request" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null; then
    base_disarm=true
  elif [[ "$review_enforce" == "true" && "$event_name" == "pull_request_review" && "$action" == "dismissed" && "$draft" == "false" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    jq -e --arg reviewer "$reviewer" 'index($reviewer) != null' <<<"$reviewers_json" >/dev/null; then
    base_disarm=true
  elif [[ "$review_enforce" == "true" && "$event_name" == "issue_comment" && "$action" == "deleted" && "$issue_open" == "true" && "$has_pull_request" == "true" ]] &&
    jq -e --arg login "$login" 'index($login) != null' <<<"$allowlist_json" >/dev/null &&
    jq -e --arg reviewer "$reviewer" 'index($reviewer) != null' <<<"$reviewers_json" >/dev/null; then
    base_disarm=true
  fi

  if [[ "$enforce" == "true" && "$base_disarm" == "true" ]] &&
    { ! jq -e --arg actor "$actor" 'index($actor) != null' <<<"$trigger_actors_json" >/dev/null ||
      ! jq -e --arg actor "$triggering_actor" 'index($actor) != null' <<<"$trigger_actors_json" >/dev/null; }; then
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
