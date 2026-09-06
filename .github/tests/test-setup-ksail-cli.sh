#!/usr/bin/env bash
# Exercise the actual installer against a controlled Homebrew command boundary.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

action="$root/setup-ksail-cli/action.yaml"
yq -r '.runs.steps[] | select(.run != null) | .run' "$action" > "$tmp/install.sh"
mkdir "$tmp/bin"
cat > "$tmp/bin/brew" <<'BREW'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$BREW_CALLS"
case "$*" in
  'tap devantler-tech/tap' | 'trust --tap devantler-tech/tap' | 'install --cask devantler-tech/tap/ksail') ;;
  *) echo "Unexpected brew command: $*" >&2; exit 99 ;;
esac
if [[ "$1" == "$FAIL_COMMAND" ]]; then
  count="$(grep -c "^$1 " "$BREW_CALLS")"
  if (( count <= FAIL_COUNT )); then exit 42; fi
fi
BREW
chmod +x "$tmp/bin/brew"
export PATH="$tmp/bin:$PATH" GITHUB_ACTION_PATH="$root/setup-ksail-cli"
export RETRY_BASE_DELAY=0 RETRY_MAX_ATTEMPTS=3 RETRY_MAX_DELAY=0
export BREW_CALLS="$tmp/calls" FAIL_COMMAND FAIL_COUNT

# Run the extracted installer and compare its exit status and complete call order.
check() {
  local name="$1" expected_status="$2" expected_calls="$3" status=0
  : > "$BREW_CALLS"
  bash "$tmp/install.sh" > "$tmp/output" 2>&1 || status=$?
  if [[ "$status" != "$expected_status" || "$(cat "$BREW_CALLS")" != "$expected_calls" ]]; then
    echo "FAIL: $name (exit $status, expected $expected_status)" >&2
    cat "$tmp/output" "$BREW_CALLS" >&2
    exit 1
  fi
  echo "PASS: $name"
}
tap='tap devantler-tech/tap'
trust='trust --tap devantler-tech/tap'
install='install --cask devantler-tech/tap/ksail'
FAIL_COMMAND='' FAIL_COUNT=0
check 'trust only the canonical tap before explicitly installing its cask' 0 "$tap
$trust
$install"
FAIL_COMMAND=tap FAIL_COUNT=2
check 'transient tap failure recovers before trust' 0 "$tap
$tap
$tap
$trust
$install"
FAIL_COMMAND=tap FAIL_COUNT=3
check 'exhausted tap failure stops before trust and install' 42 "$tap
$tap
$tap"
FAIL_COMMAND=trust FAIL_COUNT=1
check 'trust failure is fatal and never retried' 42 "$tap
$trust"
FAIL_COMMAND=install FAIL_COUNT=2
check 'transient cask download failure recovers' 0 "$tap
$trust
$install
$install
$install"
FAIL_COMMAND=install FAIL_COUNT=3
check 'exhausted installation fails the action' 42 "$tap
$trust
$install
$install
$install"

# The external setup action's channel cannot be exercised offline. Pin its input
# here; the macOS/Linux CI matrix performs the real setup and installs this cask.
stable="$(yq -r '.runs.steps[] | select((.uses // "") | test("^Homebrew/actions/setup-homebrew@")) | .with.stable' "$action")"
[[ "$stable" == true ]] || { echo 'FAIL: Homebrew must use its released channel' >&2; exit 1; }
echo 'PASS: released Homebrew channel'
