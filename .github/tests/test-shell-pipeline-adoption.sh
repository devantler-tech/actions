#!/usr/bin/env bash
# Prove the real CI scope rejects a regression in each script-owning directory.
# Only disposable copies are changed; none of the scanned scripts is executed.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: shell pipeline adoption: $*" >&2; exit 1; }

scopes="$(yq -er '.jobs.lint-shell-pipelines.env.SCAN_PATHS' "$root/.github/workflows/ci.yaml")" ||
  fail 'CI must declare its real script scope'
GOWORK=off go -C "$root/validate-shell-pipelines" build -mod=readonly -o "$work/guard" .
"$work/guard" --root "$root" --paths "$scopes"

files=(
  .scripts/retry.sh
  .github/scripts/resolve-world-at-ruin-regression-base.sh
  .github/tests/test-update-agent-skills-mark-internal.sh
  guard-installed-skill-edits/guard-installed-skill-edits.sh
  update-agent-skills/mark-internal.sh
)
fixture="$work/consumer"
mkdir -p "$fixture"
git -C "$fixture" init -q
for file in "${files[@]}"; do
  mkdir -p "$fixture/$(dirname "$file")"
  cp "$root/$file" "$fixture/$file"
done
git -C "$fixture" add -- "${files[@]}"
"$work/guard" --root "$fixture" --paths "$scopes" > "$work/clean.log" 2>&1 ||
  fail 'unmodified real scripts must pass in the consumer fixture'

for file in "${files[@]}"; do
  # Literal source text: this unsafe command is parsed, never run.
  printf '\nprintf "pipeline regression\\n" | grep -q regression\n' >> "$fixture/$file"
  rc=0
  "$work/guard" --root "$fixture" --paths "$scopes" > "$work/finding.log" 2>&1 || rc=$?
  [[ "$rc" == 1 ]] || fail "$file: expected a finding, got exit $rc"
  grep -qF "\"$file\":" "$work/finding.log" || fail "$file: missing file diagnostic"
  grep -qF 'grep -q can stop a pipe early' "$work/finding.log" || fail "$file: unrelated failure"
  cp "$root/$file" "$fixture/$file"
  echo "PASS: CI scope rejects a pipeline regression in $file"
done
"$work/guard" --root "$fixture" --paths "$scopes" > "$work/restored.log" 2>&1 ||
  fail 'restored consumer fixture must pass'
echo 'PASS: real script adoption covers every selected directory without executing its scripts'
