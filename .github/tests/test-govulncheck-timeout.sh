#!/usr/bin/env bash
# Guards the govulncheck job's runtime safety controls in
# validate-go-project.yaml (actions#593). A cold-cache scan of a large module
# runs ~14 min and a clean run crossed the old 15-min bound, so Actions
# cancelled a passing scan and failed the required check. The floor below keeps
# headroom over that observed runtime while preserving a *finite* ceiling and
# the GOMEMLIMIT heap cap — so neither control can silently regress.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"
min_timeout="${2:-20}"

status=0

timeout="$(yq -r '.jobs.govulncheck."timeout-minutes" // ""' "$workflow")"
if [[ -z "$timeout" || "$timeout" == "null" ]]; then
  echo "::error file=$workflow::govulncheck job must set a finite timeout-minutes (found none)"
  status=1
elif ((timeout < min_timeout)); then
  echo "::error file=$workflow::govulncheck timeout-minutes must be >= $min_timeout to survive a cold-cache scan (actions#593); got $timeout"
  status=1
fi

gomemlimit="$(yq -r '.jobs.govulncheck.env.GOMEMLIMIT // ""' "$workflow")"
if [[ -z "$gomemlimit" || "$gomemlimit" == "null" ]]; then
  echo "::error file=$workflow::govulncheck job must keep the GOMEMLIMIT heap cap so the GC stays under the host RAM ceiling"
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "govulncheck timeout ($timeout min) and GOMEMLIMIT ($gomemlimit) safety controls present"
fi

exit "$status"
