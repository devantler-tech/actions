#!/usr/bin/env bash
# Urgent mirror of the maintained catalogue's declared container compiler guard.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
yq -o=json '.' "$root/.github/workflows/lint.yaml" >"$scratch/lint.json"
yq -o=json '.' "$root/.github/workflows/validate-go-project.yaml" >"$scratch/go.json"
jq -s '{lint:.[0],go:.[1]}' "$scratch/lint.json" "$scratch/go.json" >"$scratch/actual.json"
cat >"$scratch/admit.jq" <<'JQ'
def setup: [.jobs.lint.steps[] | select(.id == "setup-go")];
def ml: [.jobs.lint.steps[] | select(.id == "ml")];
(.go | setup) as $go | (.lint | setup) as $lint
| ($go | length) == 1 and ($lint | length) == 1
and ($go[0] | (has("if") | not) and .with["go-version-file"] == "${{ needs.changes.outputs.module-directory }}/go.mod")
and ($lint[0] | .if == "${{ inputs.go-version-file != '' }}" and .with["go-version-file"] == "${{ inputs.go-version-file }}")
and all([$go[0],$lint[0]][]; .uses | test("^actions/setup-go@[0-9a-f]{40}$"))
and ($go[0].with | keys == ["go-version-file"])
and ($lint[0].with | keys == ["go-version-file"])
and (.go | ml | length) == 1 and (.lint | ml | length) == 1
and (.go | ml | .[0].env.GOTOOLCHAIN) == "go${{ steps.setup-go.outputs.go-version }}"
and (.lint | ml | .[0].env.GOTOOLCHAIN) == "${{ inputs.go-version-file != '' && format('go{0}', steps.setup-go.outputs.go-version) || 'local' }}"
and (.go.jobs.lint.steps | map(.id) | index("setup-go") < index("ml"))
and (.lint.jobs.lint.steps | map(.id) | index("setup-go") < index("ml"))
JQ
admit() { jq -e -f "$scratch/admit.jq" "$1" >/dev/null; }
if ! admit "$scratch/actual.json"; then
  echo 'TEST FAIL -- MegaLinter container does not use its declared setup-go compiler' >&2
  exit 1
fi
count=0
for mutation in \
  'del(.go.jobs.lint.steps[] | select(.id == "ml") | .env.GOTOOLCHAIN)' \
  '(.go.jobs.lint.steps[] | select(.id == "ml") | .env.GOTOOLCHAIN)="local"' \
  '(.go.jobs.lint.steps[] | select(.id == "ml") | .env.GOTOOLCHAIN)="auto"' \
  '(.go.jobs.lint.steps[] | select(.id == "ml") | .env.GOTOOLCHAIN)="go1.26.8"' \
  '(.go.jobs.lint.steps[] | select(.id == "setup-go") | .id)="other-go"' \
  '(.go.jobs.lint.steps[] | select(.id == "setup-go") | .if)="false"' \
  '(.go.jobs.lint.steps[] | select(.id == "setup-go") | .with["go-version"])="1.26.3"' \
  '(.lint.jobs.lint.steps[] | select(.id == "ml") | .env.GOTOOLCHAIN)="local"' \
  '(.lint.jobs.lint.steps[] | select(.id == "ml") | .env.GOTOOLCHAIN)="auto"' \
  '(.lint.jobs.lint.steps[] | select(.id == "setup-go") | .if)="true"' \
  '(.lint.jobs.lint.steps[] | select(.id == "setup-go") | .with["go-version"])="1.26.3"' \
  '(.lint.jobs.lint.steps[] | select(.id == "setup-go") | .with["go-version-file"])="other/go.mod"'; do
  jq "$mutation" "$scratch/actual.json" >"$scratch/mutant.json"
  if cmp -s "$scratch/actual.json" "$scratch/mutant.json" || admit "$scratch/mutant.json"; then
    echo "TEST FAIL -- compiler binding mutation was ineffective or admitted: $mutation" >&2
    exit 1
  fi
  count=$((count + 1))
done
echo "TEST PASS -- declared container Go compiler and $count rejected binding substitutions"
