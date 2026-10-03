#!/usr/bin/env bash
# Execute the real publication step against an offline registry boundary.
# An unsigned artifact must never become selectable as a semantic version.
set -euo pipefail
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"
workflow=.github/workflows/publish-manifests.yaml
STEP='📦 Push & sign manifests artifact' yq -r '.jobs[].steps[] | select(.name == strenv(STEP)) | .run' "$workflow" >"$scratch/publish.sh"
[[ -s "$scratch/publish.sh" ]] || { echo 'FAIL: missing publication step' >&2; exit 1; }
digest='sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
artifact=ghcr.io/devantler-tech/fixture/manifests
identity='https://github.com/devantler-tech/actions/.github/workflows/publish-manifests.yaml@0123456789abcdef0123456789abcdef01234567'
cat >"$scratch/bin/flux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'flux %s\n' "$*" >>"$STATE/calls"
case "$1 $2" in
  'push artifact')
    [[ "$FAIL_AT" != push ]] || exit 1
    printf '%s\n' "$3" >"$STATE/pushed"
    case "$3" in *:1.2.3 | *:1.2.3-rc.1) printf '%s\n' "$EXPECTED_DIGEST" >"$STATE/version" ;; esac
    if [[ "$FAIL_AT" == digest ]]; then printf '{"digest":"invalid"}\n'; else printf '{"digest":"%s"}\n' "$EXPECTED_DIGEST"; fi
    ;;
  'tag artifact')
    [[ "$4" == --tag ]] || exit 64
    [[ "$FAIL_AT" != version || "$5" == latest ]] || exit 1
    if [[ "$SIGNED_PROMOTION" == true ]]; then
      [[ "$3" == "oci://$EXPECTED_ARTIFACT@$EXPECTED_DIGEST" && -f "$STATE/verified" ]] || touch "$STATE/unsafe-promotion"
    fi
    if [[ "$5" == latest ]]; then printf '%s\n' "$EXPECTED_DIGEST" >"$STATE/latest";
    else printf '%s\n' "$EXPECTED_DIGEST" >"$STATE/version"; fi
    ;;
  *) exit 67 ;;
esac
EOF
cat >"$scratch/bin/cosign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cosign %s\n' "$*" >>"$STATE/calls"
case "$1" in
  sign)
    [[ "$2" == --yes && "$3" == "$EXPECTED_ARTIFACT@$EXPECTED_DIGEST" ]] || exit 68
    [[ "$FAIL_AT" != sign ]] || exit 1
    touch "$STATE/signed"
    ;;
  verify)
    [[ "$2" == --certificate-identity && "$3" == "$EXPECTED_IDENTITY" ]] || exit 69
    [[ "$4" == --certificate-oidc-issuer && "$5" == https://token.actions.githubusercontent.com ]] || exit 70
    [[ "$6" == "$EXPECTED_ARTIFACT@$EXPECTED_DIGEST" ]] || exit 71
    [[ -f "$STATE/signed" && "$FAIL_AT" != verify ]] || exit 1
    touch "$STATE/verified"
    ;;
  *) exit 72 ;;
esac
EOF
cat >"$scratch/bin/docker" <<'EOF'
#!/usr/bin/env bash
# The legacy path resolves its already-pushed tag through Docker.
printf '%s\n' "$EXPECTED_DIGEST"
EOF
chmod +x "$scratch/bin/flux" "$scratch/bin/cosign" "$scratch/bin/docker"
fail() { echo "FAIL: $*" >&2; cat "$scratch/out" "$state/calls" >&2; exit 1; }
run_case() {
  local failure="$1" version="$2" flag="$3" caller="$4" run_id="$5"
  state="$(mktemp -d "$scratch/case.XXXXXX")"
  printf 'old-version\n' >"$state/version"
  printf 'old-latest\n' >"$state/latest"
  : >"$state/calls"
  PATH="$scratch/bin:$PATH" STATE="$state" FAIL_AT="$failure" \
    EXPECTED_DIGEST="$digest" EXPECTED_ARTIFACT="$artifact" EXPECTED_IDENTITY="$identity" \
    SIGNED_PROMOTION="$flag" ENABLE_SIGNED_PROMOTION="$flag" JOB_WORKFLOW_REF="$caller" \
    RUN_ID="$run_id" RUN_ATTEMPT=2 REGISTRY=ghcr.io OCI_NAME=devantler-tech/fixture \
    REPOSITORY=devantler-tech/fixture SERVER_URL=https://github.com REF_NAME="v$version" \
    SHA=0123456789abcdef0123456789abcdef01234567 DEPLOY_PATH=deploy \
    ACTOR=fixture GH_TOKEN=offline-fixture bash "$scratch/publish.sh" >"$scratch/out" 2>&1
}
caller="${identity#https://github.com/}"
for failure in sign push digest verify version; do
  if run_case "$failure" 1.2.3 true "$caller" 123; then fail "succeeded after $failure failure"; fi
  [[ "$(<"$state/version")" == old-version && "$(<"$state/latest")" == old-latest ]] || fail "$failure failure moved a consumer-selectable tag"
done
echo 'ok failed publication leaves release tags unchanged'
run_case none 1.2.3 true "$caller" 123 || fail 'stable release failed'
[[ "$(<"$state/version")" == "$digest" && "$(<"$state/latest")" == "$digest" ]] || fail 'stable tags were not promoted'
[[ ! -f "$state/unsafe-promotion" ]] || fail 'promoted without verification or from a mutable source'
[[ "$(<"$state/pushed")" == "oci://$artifact:staging-123-2" ]] || fail 'push exposed a version before signing'
echo 'ok stable release promotes the verified produced digest'
run_case none 1.2.3-rc.1 true "$caller" 123 || fail 'prerelease failed'
[[ "$(<"$state/version")" == "$digest" && "$(<"$state/latest")" == old-latest ]] || fail 'prerelease moved latest'
[[ ! -f "$state/unsafe-promotion" ]] || fail 'prerelease promoted without digest verification'
echo 'ok prerelease does not move latest'
for caller in '' 'devantler-tech/actions/.github/workflows/publish-manifests.yaml@main'; do
  if run_case none 1.2.3 true "$caller" 123; then fail 'missing or mutable identity accepted'; fi
  [[ ! -s "$state/calls" ]] || fail 'bad signer identity wrote to registry'
done
if run_case none 1.2.3 true "${identity#https://github.com/}" invalid; then fail 'invalid run identity accepted'; fi
[[ ! -s "$state/calls" ]] || fail 'invalid run identity wrote to registry'
default_mode="$(yq -r '.on.workflow_call.inputs["enable-signed-promotion"].default' "$workflow")"
[[ "$default_mode" == false ]] || fail 'signed promotion must remain opt-in'
run_case none 1.2.3 "$default_mode" '' 123 || fail 'legacy default changed'
[[ "$(<"$state/pushed")" == "oci://$artifact:1.2.3" && "$(<"$state/latest")" == "$digest" ]] || fail 'legacy publication changed'
echo 'ok default-off preserves existing callers and invalid identities fail before writes'
STEP='📦 Push & sign manifests artifact' yq -o=json '.jobs[].steps[] | select(.name == strenv(STEP)) | .env' "$workflow" |
  jq -e '
    .ENABLE_SIGNED_PROMOTION == "${{ inputs.enable-signed-promotion }}" and
    .JOB_WORKFLOW_REF == "${{ steps.caller.outputs.ref }}" and
    .RUN_ID == "${{ github.run_id }}" and
    .RUN_ATTEMPT == "${{ github.run_attempt }}"
  ' >/dev/null || fail 'the actual workflow does not bind its inputs to the exercised step'
echo 'ok production input and OIDC/run identity wiring'
