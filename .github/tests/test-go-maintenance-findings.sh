#!/usr/bin/env bash
# Run the production tidy/deadcode commands against clean and broken Go modules.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
workflow="$root/.github/workflows/validate-go-project.yaml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

yq -r '.jobs.tidy.steps[] | select(.name == "🧹 go mod tidy") | .run' "$workflow" > "$tmp/tidy.sh"
yq -r '.jobs.tidy.steps[] | select(.name == "❌ Fail if uncommitted changes remain (read-only mode)") | .run' "$workflow" > "$tmp/read-only.sh"
yq -r '.jobs.deadcode.steps[] | select(.name == "📥 Install deadcode") | .run' "$workflow" > "$tmp/install-deadcode.sh"
yq -r '.jobs.deadcode.steps[] | select(.name == "🔍 Check for dead code") | .run' "$workflow" > "$tmp/deadcode.sh"
for script in tidy read-only install-deadcode deadcode; do
  [[ -s "$tmp/$script.sh" ]] || { echo "Missing production $script command" >&2; exit 1; }
done
mkdir "$tmp/bin" "$tmp/module"
export GOBIN="$tmp/bin" PATH="$tmp/bin:$PATH"
bash -euo pipefail "$tmp/install-deadcode.sh"

cd "$tmp/module"
git init -q
git config user.name test
git config user.email test@example.invalid
git config commit.gpgsign false
printf 'module example.invalid/maintenance\n\ngo 1.26.0\n' > go.mod
printf 'package main\n\nfunc main() {}\n' > main.go
bash -euo pipefail "$tmp/tidy.sh"
git add go.mod main.go
git commit -qm baseline
bash -euo pipefail "$tmp/read-only.sh"
bash -euo pipefail "$tmp/deadcode.sh"
echo 'PASS: clean module passes tidy and dead-code validation'

# An unused requirement needs no network lookup: tidy removes it locally. Record
# it as the committed input so the read-only gate sees the fix as a working edit.
printf '\nrequire example.invalid/unused v1.0.0\n' >> go.mod
git add go.mod
git commit -qm untidy
untidy="$(git rev-parse HEAD)"
bash -euo pipefail "$tmp/tidy.sh"
if bash -euo pipefail "$tmp/read-only.sh" > "$tmp/tidy.log" 2>&1; then
  echo 'FAIL: untidy module passed read-only validation' >&2
  exit 1
fi
grep -qF 'Auto-fix produced changes while signed fix commits are disabled' "$tmp/tidy.log"
[[ "$(git rev-parse HEAD)" == "$untidy" ]] || { echo 'FAIL: tidy committed a fix' >&2; exit 1; }
echo 'PASS: untidy module fails with a diagnostic and no commit'

printf '\nfunc orphan() {}\n' >> main.go
if bash -euo pipefail "$tmp/deadcode.sh" > "$tmp/deadcode.log" 2>&1; then
  echo 'FAIL: unreachable function passed dead-code validation' >&2
  exit 1
fi
grep -qF 'Dead code detected' "$tmp/deadcode.log"
grep -qE 'unreachable.*orphan' "$tmp/deadcode.log"
echo 'PASS: unreachable function fails with its actual finding'
