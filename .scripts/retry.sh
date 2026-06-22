#!/usr/bin/env bash
# Bounded retry with exponential backoff for transient-failure-prone commands.
#
# Wraps a command so a composite action's *network pull* — a Homebrew tap/install,
# a registry login, a tool/toolchain download — tolerates transient registry or
# network flakes (GHCR 5xx, DNS/TLS blips) instead of redding a *required* CI check
# on infra noise rather than a real failure. See the reliability pillar of the
# actions roadmap (devantler-tech/actions#247).
#
# Shared across composite actions and resolved relative to ${GITHUB_ACTION_PATH}
# (like .scripts/ensure-gh-skill.sh) so the retry logic lives in one place —
# composite actions cannot share steps, but they can share a bundled script that
# works for both local `uses: ./<action>` callers and external
# `uses: devantler-tech/actions/<action>@<ref>` consumers.
#
# Usage:
#   bash "${GITHUB_ACTION_PATH}/../.scripts/retry.sh" <command> [args...]
#
# Tunable via environment (sensible CI defaults):
#   RETRY_MAX_ATTEMPTS   total attempts before giving up         (default 3)
#   RETRY_BASE_DELAY     seconds to wait before the first retry  (default 5)
#   RETRY_MAX_DELAY      cap on the backoff delay in seconds     (default 60)
#
# Exit status: 0 on the first success; otherwise the failing command's last exit
# status after RETRY_MAX_ATTEMPTS attempts, so a genuine failure still reds the
# check. (No `set -e`: command failure is handled explicitly, not fatally.)
set -uo pipefail

max_attempts="${RETRY_MAX_ATTEMPTS:-3}"
base_delay="${RETRY_BASE_DELAY:-5}"
max_delay="${RETRY_MAX_DELAY:-60}"

if [ "$#" -eq 0 ]; then
  echo "::error::retry.sh: no command given" >&2
  exit 2
fi

attempt=1
delay="$base_delay"
while true; do
  "$@" && exit 0
  status=$?
  if [ "$attempt" -ge "$max_attempts" ]; then
    echo "::error::'$*' failed after ${max_attempts} attempt(s) (last exit ${status})" >&2
    exit "$status"
  fi
  echo "::warning::'$*' failed (exit ${status}); attempt ${attempt}/${max_attempts}, retrying in ${delay}s" >&2
  sleep "$delay"
  attempt=$((attempt + 1))
  delay=$((delay * 2))
  if [ "$delay" -gt "$max_delay" ]; then
    delay="$max_delay"
  fi
done
