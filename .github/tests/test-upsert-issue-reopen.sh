#!/usr/bin/env bash

# Exercise upsert-issue's actual run block against a stubbed `gh` to prove that a tracking issue
# which should be open is never left closed while the step reports success (#1375).
#
# The action tracks a recurring failure with one issue. When the matching issue is closed, the
# step must reopen it, and a reopen that keeps failing must fail the step: otherwise the body is
# updated, the step succeeds, and the failure the issue exists to surface stays hidden.
#
# The reopen decision reads the issue's live state rather than the title search, because the
# search index can still report an issue as open moments after it was closed.

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
  "issue list") printf '%s\n' "$STUB_LIST_JSON" ;;
  "issue view")
    [[ "${STUB_VIEW_RC:-0}" -eq 0 ]] || exit "$STUB_VIEW_RC"
    printf '%s\n' "$STUB_LIVE_STATE"
    ;;
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

# run_case <label> <open> <list-json> <live-state> <reopen-failures> <want-rc> <want-reopens>
#          <want-closes> <want-issue>
run_case() {
  local label="$1" open_input="$2" list="$3" live="$4" reopen_failures="$5" want_rc="$6"
  local want_reopens="$7" want_closes="$8" want_issue="$9" dir rc=0 out reopens closes issue
  dir="$(mktemp -d "$work/case.XXXXXX")"
  : >"$dir/calls"
  : >"$dir/output"
  out="$(
    PATH="$work/bin:$PATH" \
      STUB_DIR="$dir" STUB_LIST_JSON="$list" STUB_LIVE_STATE="$live" \
      STUB_REOPEN_FAILURES="$reopen_failures" \
      GITHUB_ACTION_PATH="$root/upsert-issue" GITHUB_OUTPUT="$dir/output" \
      RETRY_MAX_ATTEMPTS=3 RETRY_BASE_DELAY=0 RETRY_MAX_DELAY=0 \
      TITLE="Tracking issue" BODY="body" BODY_FILE="" LABELS="" OPEN="$open_input" \
      CLOSE_COMMENT="closed" REPO="owner/repo" GH_TOKEN="stub" \
      bash "$work/upsert.sh" 2>&1
  )" || rc=$?
  reopens="$(grep -c '^issue reopen ' "$dir/calls" || true)"
  closes="$(grep -c '^issue close ' "$dir/calls" || true)"
  issue="$(sed -n 's/^issue-number=//p' "$dir/output")"

  if [[ "$rc" != "$want_rc" ]]; then
    echo "FAIL: ${label} — exit ${rc}, want ${want_rc}; output: ${out}" >&2
    failures=$((failures + 1))
    return
  fi
  if [[ "$reopens" != "$want_reopens" ]]; then
    echo "FAIL: ${label} — ${reopens} reopen call(s), want ${want_reopens}; calls: $(tr '\n' ';' <"$dir/calls")" >&2
    failures=$((failures + 1))
    return
  fi
  if [[ "$closes" != "$want_closes" ]]; then
    echo "FAIL: ${label} — ${closes} close call(s), want ${want_closes}; calls: $(tr '\n' ';' <"$dir/calls")" >&2
    failures=$((failures + 1))
    return
  fi
  if [[ "$issue" != "$want_issue" ]]; then
    echo "FAIL: ${label} — issue-number '${issue}', want '${want_issue}'" >&2
    failures=$((failures + 1))
    return
  fi
  if grep -q 'unexpected call' <<<"$out"; then
    echo "FAIL: ${label} — the stub saw an unexpected gh call; output: ${out}" >&2
    failures=$((failures + 1))
    return
  fi
  echo "ok: ${label}"
}

closed='[{"number":7,"title":"Tracking issue","state":"CLOSED"}]'
open='[{"number":7,"title":"Tracking issue","state":"OPEN"}]'
other='[{"number":3,"title":"Tracking issue (old)","state":"CLOSED"}]'

run_case "a closed issue is reopened" true "$closed" CLOSED 0 0 1 0 7
run_case "a transient reopen failure is retried" true "$closed" CLOSED 1 0 2 0 7
run_case "a reopen that keeps failing fails the step" true "$closed" CLOSED 3 1 3 0 ""
run_case "an open issue is not sent a reopen" true "$open" OPEN 0 0 0 0 7
run_case "a stale open search result still reopens a closed issue" true "$open" CLOSED 0 0 1 0 7
run_case "no matching issue creates one without a reopen" true "$other" CLOSED 0 0 0 0 99

# Closing: an open issue is closed once; an already-closed one is left alone.
run_case "an open issue is closed" false "$open" OPEN 0 0 0 1 7
run_case "an already-closed issue is not closed again" false "$closed" CLOSED 0 0 0 0 7
run_case "no matching issue is a no-op when closing" false "$other" CLOSED 0 0 0 0 ""

[[ "$failures" -eq 0 ]] || {
  echo "FAIL: ${failures} upsert-issue reopen case(s) failed" >&2
  exit 1
}
echo "PASS: upsert-issue reopens a closed tracking issue or fails the step"
