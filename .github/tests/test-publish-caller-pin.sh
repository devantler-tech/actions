#!/usr/bin/env bash

# Guards the caller-pin contract on the two publish workflows that mint keyless cosign
# certificates. The certificate's SAN records `github.job_workflow_ref`, and the cluster's
# image/artifact trust rules verify against it — so a caller that invokes these workflows by a
# branch or a moving tag can have a superseded revision mint a signature the cluster still
# trusts. The guard requires a 40-character commit SHA, the one ref form that cannot move.
#
# The behavioural half executes the guard script EXTRACTED FROM THE WORKFLOW, never a
# transcription of it, so the assertions cannot drift away from what actually ships.

set -euo pipefail

signing_workflows=(
  ".github/workflows/publish-app.yaml"
  ".github/workflows/publish-manifests.yaml"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

guard_name="🔒 Require a SHA-pinned caller"

for workflow in "${signing_workflows[@]}"; do
  [[ -f "$workflow" ]] || fail "missing workflow: $workflow"

  # Every workflow here mints a signature, which is what makes the pin load-bearing.
  mints_signature="$(yq -r \
    '[.jobs[].permissions // {} | select(has("id-token"))] | length' "$workflow")"
  [[ "$mints_signature" -ge 1 ]] ||
    fail "$workflow no longer requests id-token; re-check whether it still needs the caller pin"

  job="$(yq -r '.jobs | keys | .[0]' "$workflow")"

  guard_count="$(GUARD_NAME="$guard_name" yq -r \
    '[.jobs[].steps[] | select(.name == strenv(GUARD_NAME))] | length' "$workflow")"
  [[ "$guard_count" == "1" ]] ||
    fail "$workflow must contain exactly one '$guard_name' step; found: $guard_count"

  # github.job_workflow_ref is NOT exposed in the expression context — measured empty inside a
  # called reusable workflow (devantler-tech/actions#858). The claim only exists in the OIDC token,
  # which is also the value Fulcio copies into the certificate SAN. So the guard must be fed from a
  # resolve step that reads that claim, never from the context property.
  resolve_reads_claim="$(yq -r \
    '[.jobs[].steps[] | select(.id == "caller") | .run | select(test("job_workflow_ref"))] | length' \
    "$workflow")"
  [[ "$resolve_reads_claim" == "1" ]] ||
    fail "$workflow must resolve the caller ref from the OIDC job_workflow_ref claim (step id: caller)"

  context_property_used="$(yq -r \
    '[.. | select(tag == "!!str") | select(test("\\$\\{\\{[^}]*github\\.job_workflow_ref"))] | length' "$workflow")"
  [[ "$context_property_used" == "0" ]] ||
    fail "$workflow uses the github.job_workflow_ref expression property, which is always empty"

  guard_env="$(GUARD_NAME="$guard_name" yq -r \
    '.jobs[].steps[] | select(.name == strenv(GUARD_NAME)) | .env.JOB_WORKFLOW_REF // ""' "$workflow")"
  # shellcheck disable=SC2016 # GitHub expression compared literally.
  [[ "$guard_env" == '${{ steps.caller.outputs.ref }}' ]] ||
    fail "$workflow guard must bind JOB_WORKFLOW_REF to the resolve step output; got: $guard_env"

  # ---- feature-flag-first: opt-in input, default-off, both states covered ----
  # AGENTS.md "Shipping a new capability behind an opt-in flag" requires new reusable-workflow
  # behaviour to ship default-off so existing callers see zero behaviour change on merge. That
  # matters more than usual here: the guard only runs on a real publish, which CI never exercises
  # (the dry-run test skips the whole publish job), so a misfire would surface at release time.
  flag_default="$(yq -r '.on.workflow_call.inputs["enable-caller-pin"].default' "$workflow")"
  [[ "$flag_default" == "false" ]] ||
    fail "$workflow enable-caller-pin must default to false; got: $flag_default"

  flag_type="$(yq -r '.on.workflow_call.inputs["enable-caller-pin"].type' "$workflow")"
  [[ "$flag_type" == "boolean" ]] ||
    fail "$workflow enable-caller-pin must be a boolean input; got: $flag_type"

  # Flag OFF (the default) => neither new step runs, so a caller that omits the input is unaffected.
  # Flag ON => both run. Both states are expressed by the same guard, so assert it on both steps.
  for step_id_or_name in "caller" "$guard_name"; do
    gated="$(STEP="$step_id_or_name" yq -r \
      '[.jobs[].steps[] | select(.id == strenv(STEP) or .name == strenv(STEP)) | .if // ""] | .[0]' \
      "$workflow")"
    # shellcheck disable=SC2016 # GitHub expression compared literally.
    [[ "$gated" == '${{ inputs.enable-caller-pin }}' ]] ||
      fail "$workflow step '$step_id_or_name' must be gated on inputs.enable-caller-pin; got: $gated"
  done

  # A token request with no timeout can hang the publish job until the 6h run limit. Pin the bound
  # so removing it cannot pass silently.
  resolve_run="$(yq -r \
    '.jobs[].steps[] | select(.id == "caller") | .run' "$workflow")"
  grep -Eq 'curl [^|]*--max-time [0-9]+' <<<"$resolve_run" ||
    fail "$workflow OIDC token request must carry --max-time so it cannot hang the publish job"

  # The resolve step must precede the guard: if it ran after, steps.caller.outputs.ref would be
  # empty and the guard would fail closed on a correctly-pinned caller.
  resolve_index="$(JOB="$job" yq -r \
    '.jobs[strenv(JOB)].steps | to_entries
       | map(select(.value.id == "caller")) | .[0].key' "$workflow")"

  # Ordering matters: the pin must be decided before the job does any work that could publish or
  # sign. Checkout is the first such step in both workflows.
  guard_index="$(GUARD_NAME="$guard_name" JOB="$job" yq -r \
    '.jobs[strenv(JOB)].steps | to_entries
       | map(select(.value.name == strenv(GUARD_NAME))) | .[0].key' "$workflow")"
  checkout_index="$(JOB="$job" yq -r \
    '.jobs[strenv(JOB)].steps | to_entries
       | map(select((.value.uses // "") | test("^actions/checkout@")))
       | .[0].key' "$workflow")"
  [[ "$checkout_index" != "null" ]] ||
    fail "$workflow has no actions/checkout step to order the guard against"
  [[ "$guard_index" -lt "$checkout_index" ]] ||
    fail "$workflow guard must run before checkout (guard=$guard_index checkout=$checkout_index)"
  [[ "$resolve_index" -lt "$guard_index" ]] ||
    fail "$workflow resolve step must run before the guard (resolve=$resolve_index guard=$guard_index)"

  # ---- behavioural half: run the shipped script against every ref shape ----
  script="$(GUARD_NAME="$guard_name" yq -r \
    '.jobs[].steps[] | select(.name == strenv(GUARD_NAME)) | .run' "$workflow")"
  [[ -n "$script" ]] || fail "$workflow guard has an empty run: body"

  run_guard() {
    JOB_WORKFLOW_REF="$1" bash -euo pipefail -c "$script" >/dev/null 2>&1
  }

  sha40="0123456789abcdef0123456789abcdef01234567"
  base="devantler-tech/actions/${workflow}"

  # Accepted: exactly the shape every real caller uses today.
  run_guard "${base}@${sha40}" ||
    fail "$workflow guard rejected a 40-hex SHA caller, which every real caller uses"

  # Rejected: everything that can move, plus every near-miss on the SHA shape.
  rejected=(
    "${base}@refs/heads/main"
    "${base}@refs/tags/v1.2.3"
    "${base}@refs/pull/12/merge"
    "${base}@v10"
    "${base}@main"
    "${base}@0123456789abcdef0123456789abcdef0123456"
    "${base}@0123456789ABCDEF0123456789ABCDEF01234567"
    "${base}@${sha40}extra"
    "${base}"
    ""
  )
  for ref in "${rejected[@]}"; do
    if run_guard "$ref"; then
      fail "$workflow guard ACCEPTED a caller it must reject: '${ref:-<empty>}'"
    fi
  done

  # ---- resolve step: run the shipped decoder against a stubbed token endpoint ----
  # The guard above is only as good as the ref it is handed, and it REJECTS an empty one — so a
  # defect in this step does not surface as a bad pin, it fails every publish before checkout, in
  # every consumer at once. That is invisible to CI otherwise: the guard only runs on a real
  # publish, which the dry-run test skips. So execute the decoder here, extracted from the workflow
  # exactly as the guard is, against a token we control.
  resolve_script="$(yq -r \
    '.jobs[].steps[] | select(.id == "caller") | .run' "$workflow")"
  [[ -n "$resolve_script" ]] || fail "$workflow resolve step has an empty run: body"

  # base64url, as a JWT carries it: standard base64 with +/ swapped for -_ and padding stripped.
  b64url() { base64 | tr -d '\n' | tr '+/' '-_' | tr -d '='; }

  # Runs the shipped decoder over a JWT built from $1 and echoes the ref it resolved.
  # Returns non-zero only if the decoder itself failed.
  run_resolve() {
    local payload_json="$1" dir status
    dir="$(mktemp -d)"
    printf '{"value":"header.%s.signature"}' "$(printf '%s' "$payload_json" | b64url)" \
      >"$dir/token.json"
    # The decoder reaches the token endpoint through curl; stub it rather than the decoder.
    # shellcheck disable=SC2016 # the stub must carry the literal $TOKEN_FIXTURE, not its value here.
    printf '#!/usr/bin/env bash\ncat "$TOKEN_FIXTURE"\n' >"$dir/curl"
    chmod +x "$dir/curl"
    : >"$dir/github_output"
    set +e
    PATH="$dir:$PATH" TOKEN_FIXTURE="$dir/token.json" GITHUB_OUTPUT="$dir/github_output" \
      ACTIONS_ID_TOKEN_REQUEST_TOKEN="stub-token" \
      ACTIONS_ID_TOKEN_REQUEST_URL="https://stub.invalid/token?api-version=2.0" \
      bash -euo pipefail -c "$resolve_script" >/dev/null 2>&1
    status=$?
    set -e
    sed -n 's/^ref=//p' "$dir/github_output"
    rm -rf "$dir"
    return "$status"
  }

  expected_ref="devantler-tech/actions/${workflow}@${sha40}"

  # A JWT payload is arbitrary-length JSON, so the decoder's base64 padding arithmetic has to hold
  # for every length class. Trailing spaces are insignificant to JSON and shift the byte length by
  # one each, which is exactly what moves the encoding between the three padding cases.
  for filler in "" " " "  "; do
    payload="$(printf '{"job_workflow_ref":"%s"}%s' "$expected_ref" "$filler")"
    encoded_len=$(( $(printf '%s' "$payload" | b64url | wc -c) ))
    got="$(run_resolve "$payload")" ||
      fail "$workflow resolve step exited non-zero for a valid token (payload len ${#payload})"
    [[ "$got" == "$expected_ref" ]] ||
      fail "$workflow resolve step decoded '$got', want '$expected_ref' (base64url len $encoded_len)"
  done

  # A real token's payload carries far more than the ref — audience, repository, run ids, timestamps
  # — so its base64url encoding routinely contains '-' and '_'. GNU coreutils `base64 -d`, which is
  # what the ubuntu runner ships, REJECTS those two characters as invalid input. So a decoder that
  # dropped the alphabet translation would not return a wrong ref; it would fail the decode
  # outright, resolve to empty, and the guard would then reject a correctly-pinned caller and fail
  # every publish closed.
  #
  # ⚠️ This assertion is provable only against GNU base64. BSD/macOS `base64 -d` silently ACCEPTS
  # the URL alphabet (measured while writing this test), so removing the translation locally is a
  # no-op and this case cannot be RED-proved off-runner. It is kept because CI is where it bites.
  # Note also what would NOT be a valid strengthening: requiring the special characters to land
  # inside the ref's own encoding window is unsatisfiable, because a ref is alphanumeric plus
  # `/.-@` and those bytes do not encode to '+' or '/'.
  alphabet_payload=""
  for probe in '~~~???' '???~~~' '~?~?~?'; do
    candidate="$(printf '{"job_workflow_ref":"%s","probe":"%s"}' "$expected_ref" "$probe")"
    encoded="$(printf '%s' "$candidate" | b64url)"
    if [[ "$encoded" == *-* && "$encoded" == *_* ]]; then
      alphabet_payload="$candidate"
      break
    fi
  done
  [[ -n "$alphabet_payload" ]] ||
    fail "could not build a payload whose base64url encoding uses both '-' and '_'; the alphabet case would go untested"
  got="$(run_resolve "$alphabet_payload")" ||
    fail "$workflow resolve step exited non-zero on a base64url payload using '-' and '_'"
  [[ "$got" == "$expected_ref" ]] ||
    fail "$workflow resolve step mistranslated the base64url alphabet: got '$got', want '$expected_ref'"

  # A token with no such claim must resolve to empty rather than to something the guard would
  # accept. Empty is already in the guard's reject list above, so the two halves compose into a
  # fail-closed path — asserted here so it stays deliberate rather than incidental.
  got="$(run_resolve '{"aud":"sigstore"}')" ||
    fail "$workflow resolve step exited non-zero on a token carrying no job_workflow_ref"
  [[ -z "$got" ]] ||
    fail "$workflow resolve step invented a ref from a claimless token: '$got'"

  echo "$workflow: caller pin enforced ✅"
done
