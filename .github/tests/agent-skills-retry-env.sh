#!/usr/bin/env bash
# Both-states test for the .scripts/agent-skills-retry-env.sh opt-in that
# setup-agent-skills sources to widen the retry.sh envelope (devantler-tech/actions#514).
# Feature-flag-first requires the flag to be exercised on AND off, so this pins
# both: off leaves retry.sh's defaults untouched, on exports the widened envelope
# and retry.sh honours it.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$repo_root/.scripts/agent-skills-retry-env.sh"
retry="$repo_root/.scripts/retry.sh"

# ── off (explicit) → envelope vars stay unset ──
(
  unset RETRY_MAX_ATTEMPTS RETRY_BASE_DELAY RETRY_MAX_DELAY
  # shellcheck source=/dev/null
  source "$script" "false"
  [ -z "${RETRY_MAX_ATTEMPTS:-}${RETRY_BASE_DELAY:-}${RETRY_MAX_DELAY:-}" ]
) || { echo "::error::flag off must not set the retry envelope"; exit 1; }
echo "✅ off: envelope untouched (retry.sh fast-fail defaults apply)"

# ── missing arg → treated as off ──
(
  unset RETRY_MAX_ATTEMPTS
  # shellcheck source=/dev/null
  source "$script"
  [ -z "${RETRY_MAX_ATTEMPTS:-}" ]
) || { echo "::error::a missing flag must default to off"; exit 1; }
echo "✅ default (no arg): envelope untouched"

# ── on → widened envelope exported with the documented values ──
(
  # shellcheck source=/dev/null
  source "$script" "true"
  [ "${RETRY_MAX_ATTEMPTS:-}" = "5" ] &&
    [ "${RETRY_BASE_DELAY:-}" = "10" ] &&
    [ "${RETRY_MAX_DELAY:-}" = "45" ]
) || { echo "::error::flag on must export the widened envelope (5 / 10 / 45)"; exit 1; }
echo "✅ on: widened envelope exported (5 attempts, 10s→45s)"

# ── on → retry.sh actually HONORS the widened envelope: a 4-failure burst that
#    the default 3-attempt envelope could never survive succeeds on the 5th try. ──
counter=$(mktemp)
flaky=$(mktemp)
trap 'rm -f "$counter" "$flaky"' EXIT
printf '0' > "$counter"
cat > "$flaky" <<EOF
#!/usr/bin/env bash
n=\$(( \$(cat "$counter") + 1 )); printf '%s' "\$n" > "$counter"
[ "\$n" -ge 5 ]
EOF
chmod +x "$flaky"
(
  # shellcheck source=/dev/null
  source "$script" "true"
  # Collapse the backoff so the test is instant; the attempt COUNT (from the
  # sourced RETRY_MAX_ATTEMPTS=5) is the behaviour under test.
  export RETRY_BASE_DELAY=0 RETRY_MAX_DELAY=0
  bash "$retry" "$flaky"
) || { echo "::error::widened envelope should ride out a 4-failure burst"; cat "$counter"; exit 1; }
if [ "$(cat "$counter")" != "5" ]; then
  echo "::error::expected retry.sh to make 5 attempts, got $(cat "$counter")"; exit 1
fi
echo "✅ on: retry.sh rides out a 4-failure burst (5 attempts) with the widened envelope"

# ── action↔helper wiring (lockstep) — the unit checks above prove the helper, but
#    would stay green if setup-agent-skills stopped forwarding the input,
#    misspelled the env var, or dropped the `source` call, leaving consumers who
#    enable the opt-in silently on the defaults. Pin that wiring here. ──
ay="$repo_root/setup-agent-skills/action.yaml"
fwd="$(yq -r '.runs.steps[] | select(.id=="install") | .env.INPUT_EXPERIMENTAL_RATE_LIMIT_RETRY' "$ay")"
case "$fwd" in
  *inputs.experimental-rate-limit-retry*) : ;;
  *) echo "::error::setup-agent-skills must forward the experimental-rate-limit-retry input into INPUT_EXPERIMENTAL_RATE_LIMIT_RETRY (got: $fwd)"; exit 1 ;;
esac
# shellcheck disable=SC2016  # match the literal source line, not an expansion
if ! yq -r '.runs.steps[] | select(.id=="install") | .run' "$ay" \
  | grep -qF 'source "${GITHUB_ACTION_PATH}/../.scripts/agent-skills-retry-env.sh" "${INPUT_EXPERIMENTAL_RATE_LIMIT_RETRY:-false}"'; then
  echo "::error::setup-agent-skills must source agent-skills-retry-env.sh with INPUT_EXPERIMENTAL_RATE_LIMIT_RETRY"
  exit 1
fi
echo "✅ wiring: setup-agent-skills forwards the opt-in input and sources the helper"

echo "all agent-skills-retry-env checks passed"
