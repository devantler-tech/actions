#!/usr/bin/env bash
# Enable the widened retry.sh envelope for the agent-skills registry pulls when
# the experimental rate-limit-retry opt-in is on (default off). The opt-in lives
# in this one shared, tested place so both states are covered in CI rather than
# buried in an action's inline `run:` block. See devantler-tech/actions#514.
#
# SOURCE this script (don't execute it) so the exports land in the caller's
# shell:
#   source "${GITHUB_ACTION_PATH}/../.scripts/agent-skills-retry-env.sh" "<true|false>"
#
# When the first argument is exactly "true", it widens the shared retry.sh
# envelope (5 attempts on a 10s→45s backoff ≈ 115s of retry) so a transient
# GitHub rate-limit 403 during a Dependabot burst — which clears as the burst
# subsides — does not red a required check. Any other value is a no-op, leaving
# retry.sh's fast-fail defaults in place, so no consumer's behaviour changes
# until the opt-in is deliberately enabled.
#
# No `set -e`/`pipefail` here: this is sourced into the caller, so it must not
# alter the caller's shell options.
if [ "${1:-false}" = "true" ]; then
  export RETRY_MAX_ATTEMPTS=5
  export RETRY_BASE_DELAY=10
  export RETRY_MAX_DELAY=45
fi
