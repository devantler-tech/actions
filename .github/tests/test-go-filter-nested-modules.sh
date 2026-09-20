#!/usr/bin/env bash
# Contract: validate-go-project.yaml `go` path-filter covers nested modules
# (actions#1133). Root-only go.mod/go.sum/.golangci.yml|.yaml miss nested
# modules while **/*.go is already recursive. Nested allowlists already use
# both-forms; go/golangci must match that shape.
set -euo pipefail
workflow="${1:-.github/workflows/validate-go-project.yaml}"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$workflow" ] || fail "workflow not found: $workflow"
command -v yq >/dev/null 2>&1 || fail "yq is required"
filters="$(yq -r '.jobs.changes.steps[] | select(.id == "filter") | .with.filters // ""' "$workflow")"
[ -n "$filters" ] || fail "could not extract paths-filter filters from $workflow"
filter_body="$(grep -v '^[[:space:]]*#' <<<"$filters" || true)"
section() { awk -v key="$1" '$0 ~ "^" key ":" {f=1;next} /^[a-zA-Z_-]+:/{f=0} f' <<<"$filter_body"; }
go_filter="$(section go)"
[ -n "$go_filter" ] || fail "empty go filter"
require_glob() {
  local glob="$1"
  grep -F -- "- '$glob'" <<<"$go_filter" >/dev/null || fail "go filter missing '$glob'"
}
require_glob '**/*.go'
require_glob 'go.mod'
require_glob 'go.sum'
require_glob '.golangci.yml'
require_glob '.golangci.yaml'
require_glob '**/go.mod'
require_glob '**/go.sum'
require_glob '**/.golangci.yml'
require_glob '**/.golangci.yaml'
echo "PASS: go filter covers nested modules ($workflow)"
