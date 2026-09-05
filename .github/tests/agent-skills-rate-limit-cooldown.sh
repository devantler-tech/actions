#!/usr/bin/env bash
# Exercise the action's real install step, retry policy, and partial-install
# recovery. Only the external CLI and wall clock are replaced.
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
yq -r '.runs.steps[] | select(.id == "install") | .run' \
  "$repo_root/setup-agent-skills/action.yaml" >"$tmp/install.sh"
default_flag=$(yq -r '.inputs.experimental-rate-limit-retry.default' \
  "$repo_root/setup-agent-skills/action.yaml")

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Every sleep advances a virtual clock. The production retry loop still chooses
# the delays, so a test cannot accidentally replace the behavior it asserts.
cat >"$tmp/bin/sleep" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 1 && $1 =~ ^[0-9]+$ ]] || exit 98
printf '%s\n' "$1" >> "$CASE_DIR/delays"
printf '%s\n' "$(( $(cat "$CASE_DIR/clock") + $1 ))" > "$CASE_DIR/clock"
SH

cat >"$tmp/bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# Reject an incorrect install request instead of accepting arbitrary mock calls.
[[ $# == 10 || $# == 11 ]] || exit 98
[[ $1 == skill && $2 == install && $3 == devantler-tech/agent-skills &&
   $4 == ways-of-working && $5 == --agent && $6 == claude-code &&
   $7 == --scope && $8 == project && $9 == --pin && ${10} == v1.5.0 ]] || exit 98
[[ $# == 10 || ${11} == --force ]] || exit 98
count=$(( $(cat "$CASE_DIR/count") + 1 ))
printf '%s\n' "$count" > "$CASE_DIR/count"
now=$(cat "$CASE_DIR/clock")
last=$(cat "$CASE_DIR/last")
printf '%s\n' "$now" > "$CASE_DIR/last"
printf '%s %s %s\n' "$count" "$now" "${11:-normal}" >> "$CASE_DIR/calls"

case "$SCENARIO" in
  immediate) ;;
  transient)
    if (( count < 3 )); then
      echo "temporary transport failure" >&2
      exit 73
    fi
    ;;
  cooldown|partial)
    # An early retry restarts the quiet period, reproducing sustained throttling.
    if (( count == 1 || now - last < 60 )) && [[ $# == 10 ]]; then
      echo "HTTP 403: You have exceeded a secondary rate limit." >&2
      exit 75
    fi
    if [[ $SCENARIO == partial && $# == 10 ]]; then
      echo "skills already installed: ways-of-working (use --force to overwrite)" >&2
      exit 1
    fi
    ;;
  repeated|exhaust)
    if [[ $SCENARIO == exhaust ]] || (( count < 5 )); then
      echo "HTTP 403: You have exceeded a secondary rate limit." >&2
      exit 75
    fi
    ;;
  permanent)
    echo "HTTP 403: Resource not accessible by integration" >&2
    exit 78
    ;;
  *) exit 98 ;;
esac
printf 'installed at %s\n' "$now" > "$CASE_DIR/installed"
echo "Installed ways-of-working"
SH
chmod +x "$tmp/bin/gh" "$tmp/bin/sleep"

run_case() {
  local name=$1 flag=$2 scenario=$3 expected_status=$4 expected_calls=$5 expected_delays=$6
  local case_dir="$tmp/$name" status=0 actual_delays
  mkdir -p "$case_dir"
  printf '0\n' >"$case_dir/clock"
  printf '0\n' >"$case_dir/count"
  printf '0\n' >"$case_dir/last"
  : >"$case_dir/delays"
  : >"$case_dir/output"
  (
    unset RETRY_MAX_ATTEMPTS RETRY_BASE_DELAY RETRY_MAX_DELAY
    export PATH="$tmp/bin:$PATH" CASE_DIR="$case_dir" SCENARIO="$scenario"
    export GITHUB_ACTION_PATH="$repo_root/setup-agent-skills"
    export GITHUB_OUTPUT="$case_dir/output" TMPDIR="$case_dir"
    export INPUT_SKILLS='devantler-tech/agent-skills ways-of-working@v1.5.0'
    export INPUT_AGENTS=claude-code INPUT_SCOPE=project
    if [[ $flag == no-env ]]; then
      unset INPUT_EXPERIMENTAL_RATE_LIMIT_RETRY
    else
      [[ $flag != omitted ]] || flag="$default_flag"
      export INPUT_EXPERIMENTAL_RATE_LIMIT_RETRY="$flag"
    fi
    bash "$tmp/install.sh"
  ) >"$case_dir/log" 2>&1 || status=$?
  [[ $status == "$expected_status" ]] || {
    cat "$case_dir/log" >&2
    fail "$name: expected exit $expected_status, got $status"
  }
  [[ $(cat "$case_dir/count") == "$expected_calls" ]] ||
    fail "$name: expected $expected_calls CLI calls, got $(cat "$case_dir/count")"
  actual_delays=$(paste -sd, "$case_dir/delays")
  [[ $actual_delays == "$expected_delays" ]] ||
    fail "$name: expected delays '$expected_delays', got '$actual_delays'"
  if [[ $expected_status == 0 ]]; then
    [[ -f "$case_dir/installed" ]] || fail "$name: no installation was completed"
    [[ $(cat "$case_dir/output") == $'installed-skills<<EOF\ndevantler-tech/agent-skills/ways-of-working@v1.5.0\nEOF' ]] ||
      fail "$name: action output must report the installed pinned skill exactly once"
  else
    [[ ! -e "$case_dir/installed" && ! -s "$case_dir/output" ]] ||
      fail "$name: failed installation must not report success"
  fi
  echo "PASS: $name"
}

# RED on the old opt-in: all four waits are below the required quiet period.
run_case cooldown true cooldown 0 2 60
run_case partial-recovery true partial 0 3 60
[[ $(tail -n 1 "$tmp/partial-recovery/calls") == '3 60 --force' ]] ||
  fail "partial recovery must force only the already-installed retry, without another sleep"
run_case repeated-throttle true repeated 0 5 60,120,240,240
run_case bounded-exhaustion true exhaust 75 5 60,120,240,240
run_case permanent-failure true permanent 78 5 60,120,240,240
[[ $(cat "$tmp/bounded-exhaustion/clock") == 660 ]] ||
  fail "the opt-in must cap total scheduled wait at eleven minutes"
run_case immediate-success true immediate 0 1 ''
run_case explicit-off false transient 0 3 5,10
run_case omitted-input omitted transient 0 3 5,10
run_case absent-environment no-env transient 0 3 5,10
run_case non-true-input TRUE transient 0 3 5,10
run_case off-stays-bounded false exhaust 75 3 5,10
echo "PASS: action retry policy honors cooldown, bounds failure, and preserves opt-out behavior"
