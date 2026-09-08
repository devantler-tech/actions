#!/usr/bin/env bash
# Guards the runtime safety controls on validate-go-project.yaml's memory-hungry
# Go analysis jobs (actions#593, ksail#6957).
#
# TIMEOUT (govulncheck). A cold-cache scan of a large module runs ~14 min and a
# clean run crossed the old 15-min bound, so Actions cancelled a passing scan and
# failed the required check. A later KSail main run finished the scan after
# 17m44s, then setup-go's cache-save post-step hit the 20-minute job limit. The
# floor below keeps headroom over both phases while preserving a *finite* ceiling.
#
# GOMEMLIMIT CEILING (every job that sets one). GOMEMLIMIT is a SOFT limit: it
# tells the GC what to aim for, and it cannot bound genuinely-live heap or the
# non-Go memory around it (the runner agent, harden-runner, and the analysis
# tools' own `go list` / type-check subprocesses). Set too close to the host's
# RAM, the Go process is permitted to grow until total system RSS crosses the
# host ceiling and the HOST kills the runner mid-analysis — surfacing as an
# opaque "runner has received a shutdown signal" / exit 143 that no retry fixes.
# A presence-only check passes happily in exactly that state, which is how
# 12GiB-on-a-16GiB-runner shipped and OOM-killed ~1 vulnerability scan in 4
# (ksail#6957). Asserting the value leaves real headroom is what stops it
# regressing.
#
# The ceiling is applied to EVERY job declaring GOMEMLIMIT rather than to a list
# of job names, so a new memory-hungry job inherits the guard instead of needing
# to be remembered here.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"
min_timeout="${2:-25}"
# Max GiB any job in this workflow may hand the Go runtime. `runs-on:
# ubuntu-latest` provides 16 GB to a public repository, so this leaves half the
# host for everything GOMEMLIMIT does not govern. A private repository's
# ubuntu-latest has 8 GB, which this ceiling already exceeds, so such a consumer
# needs a larger runner and a caller-side cap below it. Raise it only alongside a
# runner with more RAM.
max_gomemlimit_gib="${3:-8}"

# The ceiling is a caller-supplied parameter that reaches an arithmetic context in
# `((value_mib > max_gomemlimit_gib * 1024))`, so it is validated the same way the
# GOMEMLIMIT values are. Without this, `8/0` raises a division-by-zero error that
# `set -e` does not abort on here: the comparison is skipped, `status` stays 0, and
# the script reports the ceiling satisfied without ever testing it. Bounding to nine
# digits also keeps `* 1024` clear of the 64-bit wrap that turns a huge ceiling into
# a tiny one, and `10#` reads a leading zero decimally rather than as octal.
if [[ ! "$max_gomemlimit_gib" =~ ^[0-9]{1,9}$ ]]; then
  echo "::error::GOMEMLIMIT ceiling must be 1-9 decimal digits so it cannot reach an arithmetic context unchecked; got '$max_gomemlimit_gib'"
  exit 1
fi
max_gomemlimit_gib=$((10#$max_gomemlimit_gib))
if ((max_gomemlimit_gib == 0)); then
  echo "::error::GOMEMLIMIT ceiling must be greater than zero; got '0'"
  exit 1
fi

status=0

timeout="$(yq -r '.jobs.govulncheck."timeout-minutes" // ""' "$workflow")"
if [[ -z "$timeout" || "$timeout" == "null" ]]; then
  echo "::error file=$workflow::govulncheck job must set a finite timeout-minutes (found none)"
  status=1
elif ((timeout < min_timeout)); then
  echo "::error file=$workflow::govulncheck timeout-minutes must be >= $min_timeout to survive a cold-cache scan and cache-save cleanup; got $timeout"
  status=1
fi

gomemlimit="$(yq -r '.jobs.govulncheck.env.GOMEMLIMIT // ""' "$workflow")"
if [[ -z "$gomemlimit" || "$gomemlimit" == "null" ]]; then
  echo "::error file=$workflow::govulncheck job must keep the GOMEMLIMIT heap cap so the GC stays under the host RAM ceiling"
  status=1
fi

# Ceiling sweep over every job that sets GOMEMLIMIT.
jobs_with_limit="$(yq -r '.jobs | to_entries[] | select(.value.env.GOMEMLIMIT != null) | .key + " " + .value.env.GOMEMLIMIT' "$workflow")"

checked=0
while IFS=' ' read -r job value; do
  [[ -n "$job" ]] || continue
  checked=$((checked + 1))

  # Parse the SAME WAY GO DOES: decimally, always. Bash arithmetic treats a
  # leading zero as octal, so a bare $((gib * 1024)) reads `010GiB` as 8192 MiB
  # and waves it through the ceiling — while the Go runtime reads that exact
  # string as 10 GiB (measured: debug.SetMemoryLimit reports 10737418240). The
  # `10#` prefix removes the divergence, and it also stops `08GiB` — a value Go
  # accepts as 8 GiB — from aborting the arithmetic with "value too great for
  # base" and leaving the comparison unrun.
  value_mib=""
  if [[ "$value" =~ ^([0-9]+)(GiB|MiB)$ ]]; then
    digits="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"

    # Bound the digit count BEFORE any arithmetic. Bash integers are 64-bit and
    # wrap silently: 18014398509481985 * 1024 evaluates to 1024, and
    # 9223372036854775807 * 1024 to -1024 — both sail under the ceiling. Nine
    # digits is already a billion GiB, far beyond any real runner and far inside
    # the range where the multiply below cannot overflow.
    if ((${#digits} > 9)); then
      echo "::error file=$workflow::job '$job' GOMEMLIMIT '$value' is implausibly large; refusing to convert it, because fixed-width arithmetic on a value this size wraps and would report the headroom check as passed"
      status=1
    elif [[ "$unit" == "GiB" ]]; then
      value_mib=$((10#$digits * 1024))
    else
      value_mib=$((10#$digits))
    fi
  else
    echo "::error file=$workflow::job '$job' GOMEMLIMIT must be an integer with a GiB or MiB suffix so its headroom can be checked; got '$value'"
    status=1
  fi

  # Fail closed: a value that did not parse to a plain integer must never skip
  # the comparison and be reported as passing.
  if [[ -n "$value_mib" && ! "$value_mib" =~ ^[0-9]+$ ]]; then
    echo "::error file=$workflow::job '$job' GOMEMLIMIT parsed to a non-numeric size ('$value_mib') from '$value'; refusing to report the headroom check as passed"
    status=1
    value_mib=""
  fi

  if [[ -n "$value_mib" ]] && ((value_mib > max_gomemlimit_gib * 1024)); then
    echo "::error file=$workflow::job '$job' GOMEMLIMIT must be <= ${max_gomemlimit_gib}GiB to leave the host headroom GOMEMLIMIT does not govern (runner agent, harden-runner, go subprocesses); got $value. Above this the host OOM-kills the runner mid-analysis with an opaque exit 143."
    status=1
  fi
done <<EOF
$jobs_with_limit
EOF

# An empty sweep means the enumeration failed, not that the workflow is safe.
if ((checked == 0)); then
  echo "::error file=$workflow::found no job declaring GOMEMLIMIT; the headroom sweep examined nothing, so its result proves nothing"
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "govulncheck timeout ($timeout min) OK; GOMEMLIMIT ceiling ${max_gomemlimit_gib}GiB satisfied by $checked job(s)"
fi

exit "$status"
