#!/usr/bin/env bash
# Guards the govulncheck job's TRIGGER conditions in validate-go-project.yaml
# (devantler-tech/ksail#6373).
#
# Two independent gaps let a Go repo's default branch report green while its
# vulnerability scan had not run:
#
#   1. The job carried `github.event_name == 'pull_request'`, so it never ran on
#      the default branch at all. A vulnerability scan's verdict depends on the
#      vulnerability DATABASE as well as the diff — an advisory published after a
#      merge makes unchanged, already-merged code vulnerable — so a PR-only scan
#      structurally cannot report that. Measured on ksail: GO-2026-6061 (reachable,
#      google.golang.org/grpc < v1.82.1) was published 2026-07-27T15:30Z against a
#      pinned dependency main already had, and main kept reporting green.
#
#   2. `.govulncheck-allow.txt` was missing from the `go` path filter, so a commit
#      whose ONLY purpose is to change which advisories the gate accepts skipped the
#      gate that reads it. Measured on ksail commit c3522e89 (a `.govulncheck-allow.txt`
#      -only push to main): `🛡️ Vulnerability Scan` → skipped.
#
# Both are trigger-condition regressions that leave every consumer's default branch
# silently unscanned, so they are asserted here rather than left to prose.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"

status=0

# ── 1. The scan must not be restricted to pull_request ────────────────────────
gate="$(yq -r '.jobs.govulncheck.if // ""' "$workflow")"
if [[ -z "$gate" || "$gate" == "null" ]]; then
  echo "::error file=$workflow::govulncheck job has no 'if:' gate to verify"
  status=1
elif grep -qE "event_name[[:space:]]*==[[:space:]]*'pull_request'" <<<"$gate"; then
  echo "::error file=$workflow::govulncheck is gated on event_name == 'pull_request', so it can never run on the default branch. A vulnerability scan's verdict depends on the vulnerability database, not only on the diff — see ksail#6373."
  status=1
fi

# ── 2. Editing the allowlist must re-run the scan that consumes it ────────────
# Read the filter as text: the `filters:` value is a YAML string block handed to
# dorny/paths-filter, so it is not addressable as structured YAML from here.
filters="$(yq -r '.jobs.changes.steps[] | select(.id == "filter") | .with.filters // ""' "$workflow")"
if [[ -z "$filters" || "$filters" == "null" ]]; then
  echo "::error file=$workflow::could not read the paths-filter 'filters' block"
  status=1
else
  # Take the `go:` filter only — up to the next top-level filter key — so a match
  # under some other filter (e.g. `lintable:`) cannot false-pass this assertion.
  go_filter="$(awk '/^go:/{f=1;next} /^[a-zA-Z_-]+:/{f=0} f' <<<"$filters")"
  if ! grep -qF '.govulncheck-allow.txt' <<<"$go_filter"; then
    echo "::error file=$workflow::the 'go' path filter omits .govulncheck-allow.txt, so a commit that only edits the allowlist skips the vulnerability scan that reads it — see ksail#6373."
    status=1
  fi
fi

if [[ "$status" -eq 0 ]]; then
  echo "govulncheck runs on the default branch and is triggered by allowlist edits ✅"
fi

exit "$status"
