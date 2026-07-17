#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workflow="$repo_root/.github/workflows/create-release.yaml"
ci="$repo_root/.github/workflows/ci.yaml"

input_default="$(yq -r '.on.workflow_call.inputs."disable-issue-side-effects".default' "$workflow")"
input_type="$(yq -r '.on.workflow_call.inputs."disable-issue-side-effects".type' "$workflow")"
if [[ "$input_default" != "false" || "$input_type" != "boolean" ]]; then
  echo "create-release must keep issue-side-effect suppression opt-in" >&2
  exit 1
fi

release_run="$(
  yq -r '.jobs.release.steps[] | select(.name == "🎉 Release") | .run' "$workflow"
)"
expected_run="npx semantic-release@25.0.3 \${{ inputs.disable-issue-side-effects && '--success false --fail false' || '' }} \${{ inputs.dry-run && '--dry-run' || '' }}"
if [[ "$release_run" != "$expected_run" ]]; then
  echo "create-release must disable semantic-release success and fail hooks when opted in" >&2
  exit 1
fi

contents_permission="$(
  yq -r '.jobs.release.steps[] | select(.id == "app-token") | .with."permission-contents"' "$workflow"
)"
if [[ "$contents_permission" != "write" ]]; then
  echo "create-release must retain contents:write for tags and releases" >&2
  exit 1
fi

issues_permission="$(
  yq -r '.jobs.release.steps[] | select(.id == "app-token") | .with."permission-issues"' "$workflow"
)"
prs_permission="$(
  yq -r '.jobs.release.steps[] | select(.id == "app-token") | .with."permission-pull-requests"' "$workflow"
)"
expected_issues="\${{ !inputs.disable-issue-side-effects && 'write' || '' }}"
if [[ "$issues_permission" != "$expected_issues" || "$prs_permission" != "$expected_issues" ]]; then
  echo "create-release must drop issue and pull-request write access only when opted in" >&2
  exit 1
fi

off_state="$(yq -r '.jobs."test-create-release".with."disable-issue-side-effects" // "unset"' "$ci")"
on_state="$(yq -r '.jobs."test-create-release-no-issue-side-effects".with."disable-issue-side-effects"' "$ci")"
if [[ "$off_state" != "unset" || "$on_state" != "true" ]]; then
  echo "create-release CI must exercise the default and opted-in states" >&2
  exit 1
fi

echo "semantic-release issue side effects are opt-in disabled at least privilege"
