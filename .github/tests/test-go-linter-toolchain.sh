#!/usr/bin/env bash
# Urgent mirror of the maintained catalogue's compatible real-finding guard.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
yq -o=json '.' "$root/.github/workflows/validate-go-project.yaml" >"$scratch/go.json"
yq -o=json '.' "$root/.github/workflows/ci.yaml" >"$scratch/ci.json"
fixture_go="$(awk '$1 == "go" {print $2}' "$root/.github/tests/golangci-lint-fixture/go.mod")"
jq -s --arg target "$fixture_go" '{go:.[0],ci:.[1],target:$target}' \
  "$scratch/go.json" "$scratch/ci.json" >"$scratch/actual.json"
cat >"$scratch/admit.jq" <<'JQ'
def tool: [.jobs["golangci-lint"].steps[]? | select(.id == "golangci-lint")];
def compatible:
  type == "string" and test("^v2\\.[0-9]+\\.[0-9]+$") and
  (ltrimstr("v") | split(".") | .[1] | tonumber) >= 14;
def expected_lint_action:
  "golangci/golangci-lint-action@ba0d7d2ec06a0ea1cb5fa41b2e4a3ab91d21278a";
(.go | tool) as $go
| [.ci.jobs["test-validate-go-lint-blocks"].steps[]? | select(.id == "lint")] as $fixture
| [.ci.jobs["test-validate-go-lint-blocks"].steps[]? | select((.uses // "") | startswith("actions/setup-go@"))] as $setup
| .target == "1.27.2"
and ([$go,$fixture] | all(.[]; length == 1))
and ($go[0].uses == expected_lint_action)
and ($fixture[0].uses == expected_lint_action)
and ($go[0].with.version | compatible)
and ($fixture[0].with.version == $go[0].with.version)
and ($setup | length) == 1
and ($setup[0] | (has("if") | not) and .with["go-version-file"] == ".github/tests/golangci-lint-fixture/go.mod")
JQ
admit() { jq -e -f "$scratch/admit.jq" "$1" >/dev/null; }
if ! admit "$scratch/actual.json"; then
  echo 'TEST FAIL -- Go 1.27 native finding fixture and compatible production linter are not bound' >&2
  exit 1
fi
count=0
for mutation in \
  '(.go.jobs["golangci-lint"].steps[] | select(.id == "golangci-lint") | .with.version)="v2.11.4"' \
  '(.ci.jobs["test-validate-go-lint-blocks"].steps[] | select(.id == "lint") | .with.version)="v2.11.4"' \
  '(.ci.jobs["test-validate-go-lint-blocks"].steps[] | select(.id == "lint") | .uses)="golangci/golangci-lint-action@0000000000000000000000000000000000000000"' \
  '(.go.jobs["golangci-lint"].steps[] | select(.id == "golangci-lint") | .uses)="golangci/golangci-lint-action@0000000000000000000000000000000000000000"' \
  'del(.ci.jobs["test-validate-go-lint-blocks"].steps[] | select(.id == "lint") | .uses)' \
  '(.go.jobs["golangci-lint"].steps[] | select(.id == "golangci-lint") | .with.version)="v2.14.0-rc1"' \
  '.target="1.26"' \
  '(.ci.jobs["test-validate-go-lint-blocks"].steps[] | select((.uses // "") | startswith("actions/setup-go@")) | .if)="false"'; do
  jq "$mutation" "$scratch/actual.json" >"$scratch/mutant.json"
  if cmp -s "$scratch/actual.json" "$scratch/mutant.json" || admit "$scratch/mutant.json"; then
    echo "TEST FAIL -- ineffective or admitted linter compatibility substitution: $mutation" >&2
    exit 1
  fi
  count=$((count + 1))
done
echo "TEST PASS -- real Go 1.27 finding fixture, compatible lint roles and $count rejected substitutions"
