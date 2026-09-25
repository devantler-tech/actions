#!/usr/bin/env bash

# Exercise upsert-issue's actual run block against a stubbed `gh` to prove that a tracking issue
# which should be open is never left closed while the step reports success (#1375), and that the
# action picks the right issue when several share the title.
#
# The action tracks a recurring failure with one issue. When the matching issue is closed, the
# step must reopen it, and a reopen that keeps failing must fail the step: otherwise the body is
# updated, the step succeeds, and the failure the issue exists to surface stays hidden.
#
# The reopen decision reads the issue's live state rather than the title search, because the
# search index can still report an issue as open moments after it was closed. Open and closed
# matches are searched separately, so a long history of closed copies cannot hide an open one.

set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
action="$root/upsert-issue/action.yaml"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

yq -r '.runs.steps[] | select(.id == "upsert") | .run' "$action" >"$work/upsert.sh"
[[ -s "$work/upsert.sh" ]] || {
  echo "FAIL: no run block extracted from $action" >&2
  exit 1
}

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Records every call and answers from the scenario the test configured.
set -uo pipefail
printf '%s\n' "$*" >>"$STUB_DIR/calls"
case "$1 $2" in
  "issue list")
    [[ "${STUB_LIST_RC:-0}" -eq 0 ]] || exit "$STUB_LIST_RC"
    state=""
    while [[ $# -gt 0 ]]; do
      [[ "$1" == "--state" ]] && state="$2"
      shift
    done
    case "$state" in
      open) printf '%s\n' "$STUB_OPEN_JSON" ;;
      closed) printf '%s\n' "$STUB_CLOSED_JSON" ;;
      *)
        echo "stub gh: unexpected call: issue list without --state open|closed" >&2
        exit 97
        ;;
    esac
    ;;
  "issue view") printf '%s\n' "$STUB_LIVE_STATE" ;;
  "issue edit") ;;
  "issue close") ;;
  "issue create") printf 'https://github.com/owner/repo/issues/99\n' ;;
  "issue reopen")
    attempts=$(( $(cat "$STUB_DIR/reopens" 2>/dev/null || echo 0) + 1 ))
    printf '%s\n' "$attempts" >"$STUB_DIR/reopens"
    # Fail the first STUB_REOPEN_FAILURES attempts, then succeed.
    [[ "$attempts" -gt "${STUB_REOPEN_FAILURES:-0}" ]] || {
      echo "HTTP 502: Bad Gateway" >&2
      exit 1
    }
    ;;
  *)
    echo "stub gh: unexpected call: $*" >&2
    exit 97
    ;;
esac
STUB
chmod +x "$work/bin/gh"

failures=0

# run_case <label> <open> <open-json> <closed-json> <live-state> <reopen-failures> <list-rc>
#          <want-rc> <want-reopens> <want-closes> <want-creates> <want-issue>
run_case() {
  local label="$1" open_input="$2" open_json="$3" closed_json="$4" live="$5" reopen_failures="$6"
  local list_rc="$7" want_rc="$8" want_reopens="$9" want_closes="${10}" want_creates="${11}"
  local want_issue="${12}" dir rc=0 out reopens closes creates issue problem=""
  dir="$(mktemp -d "$work/case.XXXXXX")"
  : >"$dir/calls"
  : >"$dir/output"
  out="$(
    PATH="$work/bin:$PATH" \
      STUB_DIR="$dir" STUB_OPEN_JSON="$open_json" STUB_CLOSED_JSON="$closed_json" \
      STUB_LIVE_STATE="$live" STUB_REOPEN_FAILURES="$reopen_failures" STUB_LIST_RC="$list_rc" \
      GITHUB_ACTION_PATH="$root/upsert-issue" GITHUB_OUTPUT="$dir/output" \
      RETRY_MAX_ATTEMPTS=3 RETRY_BASE_DELAY=0 RETRY_MAX_DELAY=0 \
      TITLE="Tracking issue" BODY="body" BODY_FILE="" LABELS="" OPEN="$open_input" \
      CLOSE_COMMENT="closed" REPO="owner/repo" GH_TOKEN="stub" \
      bash "$work/upsert.sh" 2>&1
  )" || rc=$?
  reopens="$(grep -c '^issue reopen ' "$dir/calls" || true)"
  closes="$(grep -c '^issue close ' "$dir/calls" || true)"
  creates="$(grep -c '^issue create ' "$dir/calls" || true)"
  issue="$(sed -n 's/^issue-number=//p' "$dir/output")"

  [[ "$rc" == "$want_rc" ]] || problem="exit ${rc}, want ${want_rc}"
  [[ -n "$problem" || "$reopens" == "$want_reopens" ]] || problem="${reopens} reopen call(s), want ${want_reopens}"
  [[ -n "$problem" || "$closes" == "$want_closes" ]] || problem="${closes} close call(s), want ${want_closes}"
  [[ -n "$problem" || "$creates" == "$want_creates" ]] || problem="${creates} create call(s), want ${want_creates}"
  [[ -n "$problem" || "$issue" == "$want_issue" ]] || problem="issue-number '${issue}', want '${want_issue}'"
  if [[ -z "$problem" ]] && grep -q 'unexpected call' <<<"$out"; then
    problem="the stub saw an unexpected gh call"
  fi
  if [[ -n "$problem" ]]; then
    echo "FAIL: ${label} — ${problem}; calls: $(tr '\n' ';' <"$dir/calls"); output: ${out}" >&2
    failures=$((failures + 1))
    return
  fi
  echo "ok: ${label}"
}

none='[]'
one='[{"number":7,"title":"Tracking issue"}]'
other='[{"number":3,"title":"Tracking issue (old)"}]'
# Numbers deliberately out of order, with a near-miss title that must be ignored.
several='[{"number":12,"title":"Tracking issue"},{"number":40,"title":"Tracking issue"},{"number":5,"title":"Tracking issue"},{"number":90,"title":"Tracking issue (old)"}]'

# Columns: label, open, open-json, closed-json, live state, reopen failures, list exit code,
# then the expected exit code, reopens, closes, creates and issue number.
run_case "a closed issue is reopened" true "$none" "$one" CLOSED 0 0 0 1 0 0 7
run_case "a transient reopen failure is retried" true "$none" "$one" CLOSED 1 0 0 2 0 0 7
run_case "a reopen that keeps failing fails the step" true "$none" "$one" CLOSED 3 0 1 3 0 0 ""
run_case "an open issue is not sent a reopen" true "$one" "$none" OPEN 0 0 0 0 0 0 7
run_case "a stale open search result still reopens" true "$one" "$none" CLOSED 0 0 0 1 0 0 7
run_case "no matching issue creates one without a reopen" true "$other" "$other" CLOSED 0 0 0 0 0 1 99
run_case "the newest of several open matches is used" true "$several" "$one" OPEN 0 0 0 0 0 0 40
run_case "an open match wins over any closed match" true "$one" "$several" OPEN 0 0 0 0 0 0 7
run_case "the newest of several closed matches is reopened" true "$none" "$several" CLOSED 0 0 0 1 0 0 40
run_case "a failed search fails the step and never creates" true "$none" "$none" CLOSED 0 1 1 0 0 0 ""

# Closing: an open issue is closed once; an already-closed one is left alone.
run_case "an open issue is closed" false "$one" "$none" OPEN 0 0 0 0 1 0 7
run_case "an already-closed issue is not closed again" false "$none" "$one" CLOSED 0 0 0 0 0 0 7
run_case "no matching issue is a no-op when closing" false "$none" "$other" CLOSED 0 0 0 0 0 0 ""
run_case "a failed search fails the closing step too" false "$none" "$none" OPEN 0 1 1 0 0 0 ""

[[ "$failures" -eq 0 ]] || {
  echo "FAIL: ${failures} upsert-issue case(s) failed" >&2
  exit 1
}
echo "PASS: upsert-issue picks the newest match, reopens a closed one, and fails rather than duplicating"
