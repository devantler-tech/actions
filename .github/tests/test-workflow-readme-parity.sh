#!/usr/bin/env bash
# Exercise the checker against real YAML and Markdown, including a missing-row ablation.
# Markdown backticks in these fixtures are literal, never shell substitutions.
# shellcheck disable=SC2016
set -euo pipefail
checker="$(cd "$(dirname "$0")/../../.scripts" && pwd)/check-workflow-readme.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
cases=0
fixture() {
  rm -rf "$repo"
  mkdir -p "$repo/.github/workflows"
  cat > "$repo/.github/workflows/scan.yaml" <<'YAML'
on:
  workflow_call:
    inputs:
      directory: {type: string}
    secrets:
      SCAN_TOKEN: {required: true}
YAML
  cat > "$repo/README.md" <<'MARKDOWN'
### Scan
[Scan](.github/workflows/scan.yaml)
#### Secrets and Inputs
| Key | Type | Description |
| --- | --- | --- |
| `directory` | Input (string) | Scan this directory. |
| `SCAN_TOKEN` | Secret | Authorize the scan. |
MARKDOWN
}
expect() {
  local label="$1" want="$2" fragment="$3" status=0
  bash "$checker" "$repo" > "$tmp/log" 2>&1 || status=$?
  if [[ "$status" != "$want" ]] || ! grep -Fq "$fragment" "$tmp/log"; then
    echo "FAIL: $label: wanted exit $want and '$fragment'; got $status"
    cat "$tmp/log"
    exit 1
  fi
  cases=$((cases + 1))
}
remove_input() {
  sed '/^| `directory` /d' "$repo/README.md" > "$tmp/removed.md"
  mv "$tmp/removed.md" "$repo/README.md"
}

fixture
expect 'documented input and secret' 0 '2 inputs/secrets across 1 reusable workflows'
remove_input
expect 'missing input row' 1 "input 'directory'"
grep -Fq 'scan.yaml' "$tmp/log"
grep -Fq 'Add' "$tmp/log"

fixture
sed '/^| `SCAN_TOKEN` /d' "$repo/README.md" > "$tmp/removed.md"
mv "$tmp/removed.md" "$repo/README.md"
expect 'missing secret row' 1 "secret 'SCAN_TOKEN'"

fixture
remove_input
cat >> "$repo/README.md" <<'MARKDOWN'
### Other workflow
[Other](.github/workflows/other.yaml)
#### Inputs
| `directory` | Used by a different workflow. |
MARKDOWN
expect 'another workflow cannot document this input' 1 "input 'directory'"

fixture
remove_input
printf '\nThe `directory` input chooses a folder.\n' >> "$repo/README.md"
expect 'prose alone is not a table entry' 1 "input 'directory'"

for fence in '```' '~~~' '````'; do
  fixture
  remove_input
  printf '\n%smarkdown\n| `directory` | Input (string) | Example only. |\n%s\n' "$fence" "$fence" >> "$repo/README.md"
  expect "fenced example $fence" 1 "input 'directory'"
done

fixture
remove_input
printf '\n<!--\n| `directory` | Input (string) | Hidden row. |\n-->\n' >> "$repo/README.md"
expect 'commented-out row is not documentation' 1 "input 'directory'"

fixture
sed '/^| --- /d' "$repo/README.md" > "$tmp/changed.md"
mv "$tmp/changed.md" "$repo/README.md"
expect 'pipe-delimited prose without a table separator' 1 "input 'directory'"

fixture
cat > "$repo/README.md" <<'MARKDOWN'
### Scan
[Scan](.github/workflows/scan.yaml)
```yaml
example: true
````
#### Secrets and Inputs
| Key | Type | Description |
| --- | --- | --- |
| `directory` | Input (string) | Scan this directory. |
| `SCAN_TOKEN` | Secret | Authorize the scan. |
MARKDOWN
expect 'longer closing fence still exposes the real table' 0 '2 inputs/secrets'

fixture
sed 's/`directory`/`directory-extra`/' "$repo/README.md" > "$tmp/changed.md"
mv "$tmp/changed.md" "$repo/README.md"
expect 'similar input name is not an exact entry' 1 "input 'directory'"

fixture
sed 's/| Secret |/| Input (string) |/' "$repo/README.md" > "$tmp/changed.md"
mv "$tmp/changed.md" "$repo/README.md"
expect 'secret incorrectly documented as an input' 1 "secret 'SCAN_TOKEN'"

fixture
cp "$repo/README.md" "$tmp/duplicate.md"
cat "$tmp/duplicate.md" >> "$repo/README.md"
expect 'ambiguous duplicate workflow section' 1 'exactly one'

fixture
sed 's/scan.yaml/missing.yaml/' "$repo/README.md" > "$tmp/changed.md"
mv "$tmp/changed.md" "$repo/README.md"
expect 'missing workflow link' 1 'scan.yaml'

fixture
cat > "$repo/README.md" <<'MARKDOWN'
### Scan
[Scan](.github/workflows/scan.yaml)
#### Inputs
| Name | Description |
| --- | --- |
| `directory` | Scan this directory. |
#### Secrets
| Name | Description |
| --- | --- |
| `SCAN_TOKEN` | Authorize the scan. |
MARKDOWN
expect 'separate input and secret tables' 0 '2 inputs/secrets'

fixture
mv "$repo/.github/workflows/scan.yaml" "$repo/.github/workflows/scan.yml"
sed 's/scan.yaml/scan.yml/' "$repo/README.md" > "$tmp/changed.md"
awk '{printf "%s\r\n", $0}' "$tmp/changed.md" > "$repo/README.md"
expect 'yml extension and CRLF README' 0 '2 inputs/secrets'

fixture
printf 'on: [push, pull_request]\njobs: {}\n' > "$repo/.github/workflows/local.yaml"
expect 'repository-owned workflow excluded' 0 '1 reusable workflows'

fixture
printf 'on: {workflow_call: null}\n' > "$repo/.github/workflows/scan.yaml"
expect 'workflow with no interface needs no rows' 0 '0 inputs/secrets across 1'

fixture
printf 'on: {workflow_call: {inputs: false}}\n' > "$repo/.github/workflows/scan.yaml"
expect 'malformed inputs cannot become an empty interface' 2 'Invalid workflow_call'

fixture
printf 'on: {workflow_call: {secrets: []}}\n' > "$repo/.github/workflows/scan.yaml"
expect 'malformed secrets cannot become an empty interface' 2 'Invalid workflow_call'

fixture
printf 'on: {workflow_call: [oops]}\n' > "$repo/.github/workflows/scan.yaml"
expect 'malformed workflow_call' 2 'Invalid workflow_call'

fixture
printf 'on: [broken\n' > "$repo/.github/workflows/scan.yaml"
expect 'invalid YAML is an operational failure' 2 'Cannot parse'

fixture
printf '\n---\non: {workflow_call: null}\n' >> "$repo/.github/workflows/scan.yaml"
expect 'multiple YAML documents cannot hide an interface' 2 'single workflow mapping'

fixture
printf 'on: push\njobs: {}\n' > "$repo/.github/workflows/scan.yaml"
expect 'empty reusable workflow census fails' 2 'No reusable workflows'

fixture
rm "$repo/README.md"
expect 'missing README fails' 2 'missing'

fixture
rm "$repo/.github/workflows/scan.yaml"
expect 'missing workflow files fail' 2 'No workflow files'

# Reproduce the original incident against the repository corpus: the same input
# mentioned elsewhere in the README must not hide its missing workflow-table row.
source_root="$(cd "$(dirname "$checker")/.." && pwd)"
fixture
rm "$repo/.github/workflows/scan.yaml"
cp -R "$source_root/.github/workflows/." "$repo/.github/workflows/"
cp "$source_root/README.md" "$repo/README.md"
expect 'repository corpus is documented' 0 'Workflow README parity OK'
sed '/^| `test-default-branch` /d' "$repo/README.md" > "$tmp/removed.md"
mv "$tmp/removed.md" "$repo/README.md"
expect 'repository missing-row ablation' 1 "validate-go-project.yaml: input 'test-default-branch'"
[[ "$(wc -l < "$tmp/log" | tr -d ' ')" == 1 ]] || {
  echo 'FAIL: the single-row ablation must report only the removed entry'
  cat "$tmp/log"
  exit 1
}

echo "Workflow README parity: $cases behavioral cases passed."
