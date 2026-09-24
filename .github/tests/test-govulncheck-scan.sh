#!/usr/bin/env bash
# Exercise the real result evaluator; only the external scanner process is a
# fixture so operational errors and malformed streams can be reproduced offline.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
script="$root/.github/actions/govulncheck/scan.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/module with spaces"
cat >"$work/scanner" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == '-format=json -scan=symbol ./...' ]] || exit 90
[[ "$PWD" == "$EXPECTED_DIR" ]] || exit 91
cat "$SCAN_FIXTURE"
exit "$SCAN_STATUS"
SH
chmod +x "$work/scanner"
export EXPECTED_DIR="$work/module with spaces"
export SCAN_FIXTURE="$work/scan.json" SCAN_STATUS=0
export GITHUB_OUTPUT="$work/output"

config='{"config":{"protocol_version":"v1.0.0","scan_level":"symbol","scan_mode":"source"}}'
called='{"finding":{"osv":"GO-2021-0113","fixed_version":"v0.3.7","trace":[{"module":"golang.org/x/text","package":"golang.org/x/text/language","function":"Parse"}]}}'
other='{"finding":{"osv":"GO-2022-1059","trace":[{"module":"golang.org/x/text","package":"golang.org/x/text/language","function":"Match"}]}}'
uncalled='{"finding":{"osv":"GO-2022-1059","trace":[{"module":"golang.org/x/text","package":"golang.org/x/text/language"}]}}'
printf '# Accepted for this fixture\r\nGO-2021-0113  # reason\r\n\r\n' >"$work/allow.txt"

check() {
  local label="$1" want="$2" expected="$3" allow="${4-}" rc=0 out
  : >"$GITHUB_OUTPUT"
  out="$(bash "$script" "$work/scanner" "$EXPECTED_DIR" "$allow" "$work/result.json" 2>&1)" || rc=$?
  if [[ "$rc" != "$want" || "$out" != *"$expected"* ]]; then
    printf 'FAIL: %s: wanted exit %s and %s; got %s\n%s\n' "$label" "$want" "$expected" "$rc" "$out" >&2
    exit 1
  fi
  case "$want" in
    0) grep -qxF 'verdict=clean' "$GITHUB_OUTPUT" ;;
    1) grep -qxF 'verdict=blocking' "$GITHUB_OUTPUT" ;;
    *) [[ ! -s "$GITHUB_OUTPUT" ]] ;;
  esac
  echo "PASS: $label"
}

printf '%s\n' "$config" "$called" >"$SCAN_FIXTURE"
check 'strict scan blocks a reachable advisory' 1 'GO-2021-0113 - BLOCKING'
cmp "$SCAN_FIXTURE" "$work/result.json"
check 'nested module honors comments and CRLF in allowlist' 0 'GO-2021-0113 - ALLOWLISTED' "$work/allow.txt"
printf '%s\n' "$config" "$called" "$called" "$other" >"$SCAN_FIXTURE"
check 'an accepted advisory cannot suppress another one' 1 'GO-2022-1059 - BLOCKING' "$work/allow.txt"
printf '%s\n' "$config" "$uncalled" >"$SCAN_FIXTURE"
check 'imported but uncalled advisories do not block' 0 'No blocking vulnerabilities'
printf '%s\n' "$config" >"$SCAN_FIXTURE"
check 'clean scan passes' 0 'No blocking vulnerabilities'
export SCAN_STATUS=2
check 'scanner failure is never interpreted as clean' 2 'operational error' "$work/allow.txt"
export SCAN_STATUS=0
: >"$SCAN_FIXTURE"
check 'empty output fails closed' 2 'invalid scan output'
printf '%s\n' "$config" '{"finding":' >"$SCAN_FIXTURE"
check 'truncated JSON fails closed' 2 'invalid scan output'
printf '%s\n' "$config" '{"finding":{"osv":"GO-2021-0113"}}' >"$SCAN_FIXTURE"
check 'finding without a trace fails closed' 2 'invalid scan output'
printf '%s\n' '{"config":{"protocol_version":"v2.0.0","scan_level":"symbol","scan_mode":"source"}}' >"$SCAN_FIXTURE"
check 'unsupported protocol fails closed' 2 'invalid scan output'
printf '%s\n' '{"config":{"protocol_version":"v1.0.0","scan_level":"package","scan_mode":"source"}}' >"$SCAN_FIXTURE"
check 'reduced scan level fails closed' 2 'invalid scan output'
printf '%s\n' "$config" "$called" >"$SCAN_FIXTURE"
check 'missing explicit allowlist remains strict' 1 'GO-2021-0113 - BLOCKING' "$work/missing.txt"
echo 'PASS: vulnerability verdict and operational failure boundaries'
