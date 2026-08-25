#!/usr/bin/env bash
set -euo pipefail

guard=${1:-.github/tests/test-ci-harden-runner-first.sh}
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ci-harden-runner-first.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'ci harden-runner negative guard: %s\n' "$1" >&2
  exit 1
}

assert_blocked() {
  local fixture=$1
  local expected=$2
  local output="$tmp_dir/output"

  if bash "$guard" "$fixture" >"$output" 2>&1; then
    fail "guard accepted invalid fixture: $fixture"
  fi

  grep -qF "$expected" "$output" ||
    fail "guard rejected $fixture without expected diagnostic: $expected"
}

cat >"$tmp_dir/missing.yaml" <<'YAML'
jobs:
  test:
    steps:
      - uses: step-security/harden-runner@05e31511f85b41b11d1cf0ef85d0992719546e2c
        with:
          egress-policy: audit
YAML

cat >"$tmp_dir/reusable.yaml" <<'YAML'
jobs:
  ci-required-checks:
    uses: ./.github/workflows/other.yaml
  test:
    steps:
      - uses: step-security/harden-runner@05e31511f85b41b11d1cf0ef85d0992719546e2c
        with:
          egress-policy: audit
YAML

cat >"$tmp_dir/scalar-steps.yaml" <<'YAML'
jobs:
  ci-required-checks:
    steps: invalid
  test:
    steps:
      - uses: step-security/harden-runner@05e31511f85b41b11d1cf0ef85d0992719546e2c
        with:
          egress-policy: audit
YAML

assert_blocked "$tmp_dir/missing.yaml" "ci-required-checks must exist as an inline job"
assert_blocked "$tmp_dir/reusable.yaml" "ci-required-checks must not call a reusable workflow"
assert_blocked "$tmp_dir/scalar-steps.yaml" "ci-required-checks must define inline steps as a sequence"

printf 'ci harden-runner negative guard: all invalid exemption shapes were blocked\n'
