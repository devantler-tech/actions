#!/usr/bin/env bash

# Run each consumer's actual patch exporter against real Git changes. Workflow edits
# must remain downloadable without reaching a contents-only signing job, and a mixed
# patch must stay intact (a rename or related edit cannot be committed in pieces).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

for workflow in lint validate-go-project; do
  file="$root/.github/workflows/$workflow.yaml"
  yq -r '.jobs.lint.steps[] | select(.id == "fixes") | .run' "$file" >"$work/export.sh"
  for enabled in false true; do
  for scenario in workflow clean ordinary new-workflow deleted-workflow mixed rename-in rename-out similar-directory nested-workflow binary-only binary-mixed mode-only mode-mixed; do
    fixture="$work/$workflow-$enabled-$scenario"
    mkdir -p "$fixture/.github/workflows" "$fixture/.github/workflows-extra" "$fixture/nested/.github/workflows" "$fixture/nested/module" "$fixture/../artifacts-$workflow-$enabled-$scenario"
    git -C "$fixture" init -q
    git -C "$fixture" config user.name test
    git -C "$fixture" config user.email test@example.invalid
    git -C "$fixture" config commit.gpgsign false
    git -C "$fixture" config core.filemode true
    printf 'original\n' >"$fixture/.github/workflows/ci.yaml"
    printf 'original\n' >"$fixture/value.txt"
    printf 'original\n' >"$fixture/.github/workflows-extra/value.yaml"
    printf 'original\n' >"$fixture/nested/.github/workflows/ci.yaml"
    printf 'before\000binary\n' >"$fixture/payload.bin"
    printf '#!/bin/sh\necho fixture\n' >"$fixture/script.sh"
    git -C "$fixture" add -- .github value.txt nested payload.bin script.sh
    git -C "$fixture" commit -qm base

    changed=true
    manual=true
    case "$scenario" in
      clean) changed=false; manual=false ;;
      ordinary) printf 'formatted\n' >"$fixture/value.txt"; manual=false ;;
      workflow) printf 'formatted\n' >"$fixture/.github/workflows/ci.yaml" ;;
      new-workflow) printf 'new\n' >"$fixture/.github/workflows/new workflow.yml" ;;
      deleted-workflow) rm "$fixture/.github/workflows/ci.yaml" ;;
      mixed)
        printf 'formatted\n' >"$fixture/.github/workflows/ci.yaml"
        printf 'formatted\n' >"$fixture/value.txt"
        printf 'new\n' >"$fixture/nested/new file.txt"
        ;;
      rename-in) mv "$fixture/value.txt" "$fixture/.github/workflows/renamed.yml" ;;
      rename-out) mv "$fixture/.github/workflows/ci.yaml" "$fixture/moved.txt" ;;
      similar-directory) printf 'formatted\n' >"$fixture/.github/workflows-extra/value.yaml"; manual=false ;;
      nested-workflow) printf 'formatted\n' >"$fixture/nested/.github/workflows/ci.yaml"; manual=false ;;
      binary-only) printf 'after\000binary\n' >"$fixture/payload.bin"; manual=false ;;
      binary-mixed)
        printf 'after\000binary\n' >"$fixture/payload.bin"
        printf 'formatted\n' >"$fixture/.github/workflows/ci.yaml"
        ;;
      mode-only) chmod +x "$fixture/script.sh"; manual=false ;;
      mode-mixed)
        chmod +x "$fixture/script.sh"
        printf 'formatted\n' >"$fixture/.github/workflows/ci.yaml"
        ;;
    esac
    [[ "$enabled" == true ]] || manual=false

    artifacts="$fixture/../artifacts-$workflow-$enabled-$scenario"
    (
      cd "$fixture"
      export FIXES_ARTIFACT=megalinter-fixes-123 RUNNER_TEMP="$artifacts" GITHUB_OUTPUT="$artifacts/outputs"
      export MANUAL_WORKFLOW_FIXES="$enabled"
      bash -euo pipefail "$work/export.sh"
    ) >"$artifacts/log" 2>&1 || fail "$workflow/$scenario exporter failed"
    grep -qxF "changed=$changed" "$artifacts/outputs" || fail "$workflow/$scenario changed output"
    grep -qxF "manual-required=$manual" "$artifacts/outputs" || fail "$workflow/$scenario manual routing"
    grep -qxF 'artifact-name=megalinter-fixes-123' "$artifacts/outputs" || fail "$workflow/$scenario artifact identity"
    if [[ "$manual" == true ]]; then
      grep -qF '::warning::' "$artifacts/log" || fail "$workflow/$scenario needs an actionable warning"
      grep -qF 'git apply' "$artifacts/log" || fail "$workflow/$scenario warning must explain recovery"
    elif grep -qF '::warning::' "$artifacts/log"; then
      fail "$workflow/$enabled/$scenario emitted an unsolicited manual-routing warning"
    fi
    patch="$artifacts/megalinter-fixes-123.patch"
    if [[ "$changed" == true ]]; then
      [[ -s "$patch" ]] || fail "$workflow/$scenario lost the patch"
      # Stage the fixture's intended result only AFTER export, so additions above really
      # are untracked when the production exporter sees them.
      git -C "$fixture" add -- .github nested payload.bin script.sh
      [[ ! -e "$fixture/value.txt" ]] || git -C "$fixture" add -- value.txt
      [[ ! -e "$fixture/moved.txt" ]] || git -C "$fixture" add -- moved.txt
      expected="$(git -C "$fixture" write-tree)"
      # Transfer only committed objects. A local clone also copies unreachable
      # blobs staged above, which could let git apply recover omitted binary
      # payloads from the fixture's object store instead of from the artifact.
      git clone -q --no-local "$fixture" "$artifacts/replay"
      git -C "$artifacts/replay" apply --index "$patch" || fail "$workflow/$scenario patch cannot be applied"
      [[ "$(git -C "$artifacts/replay" write-tree)" == "$expected" ]] || fail "$workflow/$scenario exported only part of the fix"
    else
      [[ ! -s "$patch" ]] || fail "$workflow/$scenario created a patch for a clean tree"
    fi
    echo "PASS: $workflow/$enabled/$scenario"
  done
  done

  # The job output is the authorization handed to the existing signer. Require an
  # explicit false manual flag so a missing exporter output cannot authorize a commit.
  output="$(yq -r '.jobs.lint.outputs."fixes-created"' "$file")"
  [[ "$output" == "\${{ steps.fixes.outputs.changed == 'true' && steps.fixes.outputs.manual-required == 'false' }}" ]] ||
    fail "$workflow must withhold workflow patches from the signer"

  # Every changed patch, including a manual one, must still use the upload path. The
  # existing contract test covers the Go caller's full opt-in/fork/bot boundary.
  upload_if="$(yq -r '.jobs.lint.steps[] | select(.uses != null and (.uses | test("^actions/upload-artifact@"))) | .if' "$file")"
  [[ "$upload_if" == *"steps.fixes.outputs.changed == 'true'"* && "$upload_if" != *manual-required* ]] ||
    fail "$workflow must retain manual patches for download"

  # A failed git read must not be mistaken for a clean or signable patch.
  mkdir -p "$work/not-a-repo-$workflow"
  if (cd "$work/not-a-repo-$workflow" && FIXES_ARTIFACT=x RUNNER_TEMP="$work" GITHUB_OUTPUT="$work/error-output" bash -euo pipefail "$work/export.sh") >/dev/null 2>&1; then
    fail "$workflow accepted a Git failure"
  fi
done

echo 'PASS: workflow fixes stay complete, recoverable, and out of automatic commits'
