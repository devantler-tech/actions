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
# envelope (5 attempts, waiting 60, 120, 240, 240 seconds). GitHub prescribes
# at least one minute before retrying a secondary limit when response headers
# are unavailable, then exponential backoff. gh skill does not expose those
# headers; this fallback does not resolve an exhausted primary hourly quota.
# Total scheduled wait is bounded at 660 seconds, excluding command runtime.
# https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#exceeding-the-rate-limit
# Any other value is a no-op, leaving
# retry.sh's fast-fail defaults in place, so no consumer's behaviour changes
# until the opt-in is deliberately enabled.
#
# No `set -e`/`pipefail` here: this is sourced into the caller, so it must not
# alter the caller's shell options.
if [ "${1:-false}" = "true" ]; then
  export RETRY_MAX_ATTEMPTS=5
  export RETRY_BASE_DELAY=60
  export RETRY_MAX_DELAY=240
fi
