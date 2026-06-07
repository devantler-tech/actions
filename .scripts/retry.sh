#!/usr/bin/env bash
# Bounded retry-with-backoff wrapper for transient-failure-prone commands.
#
# Realizes the "composites resilient to transient infra" reliability pillar
# (devantler-tech/actions#247 item 3): a composite that does a NETWORK PULL
# (brew install, registry pull, toolchain download) should tolerate transient
# registry/network flakes with a bounded retry + backoff so it never reds a
# *required* check on infra noise rather than on a real failure.
#
# Shared across composites via the bundled-script pattern (the same one
# .scripts/ensure-gh-skill.sh uses): composite actions cannot share steps, but
# they can share a script bundled in this repository, resolved relative to
# ${GITHUB_ACTION_PATH} so it works for both local `uses: ./<action>` callers
# and external `uses: devantler-tech/actions/<action>@<ref>` consumers:
#   bash "${GITHUB_ACTION_PATH}/../.scripts/retry.sh" <attempts> <base-delay-s> -- <cmd> [args...]
#
# Backoff is exponential: base-delay * 2^(attempt-1) seconds between tries
# (e.g. base 5 → waits 5s, then 10s, then 20s …). Exits 0 on the first success;
# on exhaustion, exits with the last attempt's status code so the caller still
# sees a genuine, persistent failure.
set -euo pipefail

usage() {
  echo "::error::Usage: retry.sh <max-attempts> <base-delay-seconds> -- <command> [args...]" >&2
  exit 2
}

# Need at least: <attempts> <base-delay> -- <command>
[ "$#" -ge 4 ] || usage
attempts="$1"
base_delay="$2"
shift 2
[ "$1" = "--" ] || usage
shift

case "$attempts" in '' | *[!0-9]*) usage ;; esac
case "$base_delay" in '' | *[!0-9]*) usage ;; esac
[ "$attempts" -ge 1 ] || usage
[ "$#" -ge 1 ] || usage

attempt=1
while true; do
  # `cmd || status=$?` runs the command with errexit suspended and captures its
  # real exit code (a bare `if cmd; then` would leave $? as 0 on the else path).
  status=0
  "$@" || status=$?
  if [ "$status" -eq 0 ]; then
    exit 0
  fi
  if [ "$attempt" -ge "$attempts" ]; then
    echo "::error::Command failed after ${attempts} attempt(s): $* (last exit ${status})" >&2
    exit "$status"
  fi
  delay=$((base_delay * (1 << (attempt - 1))))
  echo "::warning::Attempt ${attempt}/${attempts} failed (exit ${status}): $* — retrying in ${delay}s" >&2
  sleep "$delay"
  attempt=$((attempt + 1))
done
