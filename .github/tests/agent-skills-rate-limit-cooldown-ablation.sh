#!/usr/bin/env bash
# Prove the behavioral regression suite detects changes that break recovery,
# bounded waits, or the default-off consumer contract.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/repo"
mkdir -p "$fixture/.scripts" "$fixture/setup-agent-skills"

reset_fixture() {
  cp "$repo_root/.scripts/agent-skills-retry-env.sh" \
    "$repo_root/.scripts/retry.sh" \
    "$repo_root/.scripts/gh-skill-install.sh" "$fixture/.scripts/"
  cp "$repo_root/setup-agent-skills/action.yaml" "$fixture/setup-agent-skills/"
}

assert_rejected() {
  local name=$1 expected=$2 status=0
  bash "$repo_root/.github/tests/agent-skills-rate-limit-cooldown.sh" \
    "$fixture" >"$tmp/log" 2>&1 || status=$?
  [[ $status == 1 ]] || {
    cat "$tmp/log" >&2
    echo "::error::$name: expected a regression failure, got $status" >&2
    exit 1
  }
  grep -qF "$expected" "$tmp/log" || {
    cat "$tmp/log" >&2
    echo "::error::$name: failed for the wrong reason" >&2
    exit 1
  }
  echo "PASS: rejects $name"
}

reset_fixture
sed 's/RETRY_BASE_DELAY=60/RETRY_BASE_DELAY=59/' \
  "$fixture/.scripts/agent-skills-retry-env.sh" >"$tmp/changed"
mv "$tmp/changed" "$fixture/.scripts/agent-skills-retry-env.sh"
assert_rejected early-retry 'cooldown: expected 2 CLI calls, got 3'

reset_fixture
sed 's/RETRY_MAX_DELAY=240/RETRY_MAX_DELAY=480/' \
  "$fixture/.scripts/agent-skills-retry-env.sh" >"$tmp/changed"
mv "$tmp/changed" "$fixture/.scripts/agent-skills-retry-env.sh"
assert_rejected excessive-backoff "repeated-throttle: expected delays '60,120,240,240', got '60,120,240,480'"

reset_fixture
sed 's/RETRY_MAX_ATTEMPTS=5/RETRY_MAX_ATTEMPTS=6/' \
  "$fixture/.scripts/agent-skills-retry-env.sh" >"$tmp/changed"
mv "$tmp/changed" "$fixture/.scripts/agent-skills-retry-env.sh"
assert_rejected extra-attempt 'bounded-exhaustion: expected 5 CLI calls, got 6'

reset_fixture
yq -i '.inputs.experimental-rate-limit-retry.default = "true"' \
  "$fixture/setup-agent-skills/action.yaml"
assert_rejected implicit-rollout "omitted-input: expected delays '5,10', got '60,120'"

reset_fixture
sed 's/export RETRY_BASE_DELAY=60/:/' \
  "$fixture/.scripts/agent-skills-retry-env.sh" >"$tmp/changed"
mv "$tmp/changed" "$fixture/.scripts/agent-skills-retry-env.sh"
assert_rejected missing-policy 'cooldown: expected exit 0, got 75'
echo "PASS: cooldown regression suite rejects all five behavior mutations"
