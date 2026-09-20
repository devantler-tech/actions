#!/usr/bin/env bash
# Failing-input counterpart to test-go-filter-nested-modules.sh, per the repo convention
# that a gating self-test carries BOTH a passes-on-good-input and a blocks-on-bad-input
# test (AGENTS.md, "Failure-mode coverage for gating workflows").
#
# Contract: validate-go-project.yaml `go` path-filter covers nested modules
# (actions#1133). Root-only go.mod/go.sum/.golangci.yml|.yaml miss nested
# modules while **/*.go is already recursive. This counterpart proves the
# dedicated guard still bites when any required recursive glob is omitted.
set -euo pipefail

guard="${1:-.github/tests/test-go-filter-nested-modules.sh}"
fixtures="$(mktemp -d "${TMPDIR:-/tmp}/go-filter-nested-modules-blocks.XXXXXX")"
trap 'rm -rf "$fixtures"' EXIT

status=0

write_fixture() {
  local name="$1"
  local go_globs="$2"
  cat >"$fixtures/$name" <<EOF
jobs:
  changes:
    steps:
      - id: filter
        with:
          filters: |
            go:
${go_globs}
            govulncheck:
              - '.govulncheck-allow.txt'
              - '**/.govulncheck-allow.txt'
EOF
}

all_go_globs="              - '**/*.go'
              - 'go.mod'
              - 'go.sum'
              - '.golangci.yml'
              - '.golangci.yaml'
              - '**/go.mod'
              - '**/go.sum'
              - '**/.golangci.yml'
              - '**/.golangci.yaml'"

write_fixture good.yaml "$all_go_globs"

write_fixture missing-nested-gomod.yaml "              - '**/*.go'
              - 'go.mod'
              - 'go.sum'
              - '.golangci.yml'
              - '.golangci.yaml'
              - '**/go.sum'
              - '**/.golangci.yml'
              - '**/.golangci.yaml'"

write_fixture missing-nested-gosum.yaml "              - '**/*.go'
              - 'go.mod'
              - 'go.sum'
              - '.golangci.yml'
              - '.golangci.yaml'
              - '**/go.mod'
              - '**/.golangci.yml'
              - '**/.golangci.yaml'"

write_fixture missing-nested-golangci-yml.yaml "              - '**/*.go'
              - 'go.mod'
              - 'go.sum'
              - '.golangci.yml'
              - '.golangci.yaml'
              - '**/go.mod'
              - '**/go.sum'
              - '**/.golangci.yaml'"

write_fixture missing-nested-golangci-yaml.yaml "              - '**/*.go'
              - 'go.mod'
              - 'go.sum'
              - '.golangci.yml'
              - '.golangci.yaml'
              - '**/go.mod'
              - '**/go.sum'
              - '**/.golangci.yml'"

check() {
  local fixture="$1" expected="$2" out rc
  local path="$fixtures/$fixture"

  if [[ ! -f "$path" ]]; then
    echo "::error::fixture $path is missing — the negative test cannot prove the gate bites"
    status=1
    return
  fi

  out="$(bash "$guard" "$path" 2>&1)" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    echo "::error file=$path::the guard PASSED a deliberately-bad fixture — it has stopped biting. Expected it to report: $expected"
    status=1
  elif ! grep -qF "$expected" <<<"$out"; then
    echo "::error file=$path::the guard failed, but not for the expected reason. Expected a message containing: $expected"
    while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
    status=1
  else
    echo "blocks $fixture ✅"
  fi
}

check missing-nested-gomod.yaml "go filter missing '**/go.mod'"
check missing-nested-gosum.yaml "go filter missing '**/go.sum'"
check missing-nested-golangci-yml.yaml "go filter missing '**/.golangci.yml'"
check missing-nested-golangci-yaml.yaml "go filter missing '**/.golangci.yaml'"

passes() {
  local label="$1" path="$2" out rc
  if [[ ! -f "$path" ]]; then
    echo "::error::$path is missing — the accept-side control cannot run"
    status=1
    return
  fi
  out="$(bash "$guard" "$path" 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    echo "passes $label ✅"
  else
    echo "::error file=$path::the guard REJECTS $label; the negative fixtures above prove nothing about a gate that fails everything"
    while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
    status=1
  fi
}

passes "the good fixture" "$fixtures/good.yaml"
passes "the real workflow" ".github/workflows/validate-go-project.yaml"

if [[ "$status" -eq 0 ]]; then
  echo "go nested-module filter guard blocks every bad-input fixture and accepts both controls ✅"
fi

exit "$status"
