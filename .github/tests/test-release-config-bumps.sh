#!/usr/bin/env bash
#
# Verifies the `breaking-bang-commits` option of create-release.yaml by running
# semantic-release against real fixture commits — asserting the BUMP, not the
# config's shape.
#
# A shape assertion would not have caught the bug this exists to fix: a bare
# configuration silently gave `feat!:` NO RELEASE AT ALL, so a breaking change
# shipped unversioned. The config looked perfectly fine.
#
# The fixture deliberately mirrors PRODUCTION: semantic-release is run via `npx`
# with nothing installed into the workspace, exactly as the Release step does.
# An earlier version of this test installed semantic-release locally and so
# passed while the real workflow was broken.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workflow="$repo_root/.github/workflows/create-release.yaml"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The exact script the workflow runs — not a copy that could drift from it.
yq -r '.jobs.release.steps[] | select(.name | test("Teach semantic-release")) | .run' \
  "$workflow" > "$work/inject.sh"

fixture="$work/fixture"
mkdir -p "$fixture" && cd "$fixture"
git init -q .
git config user.email ci@example.com
git config user.name ci
git config commit.gpgsign false
git init -q --bare "$work/origin.git"
git remote add origin "$work/origin.git"
printf 'node_modules\n' > .gitignore
echo base > f.txt
git add f.txt .gitignore
git commit -q -m "chore: base"
git tag v1.0.0
branch="$(git rev-parse --abbrev-ref HEAD)"
git push -q origin "$branch" --tags

# $1 commit message, $2 expected bump, $3 inject? (yes|no)
assert_bump() {
  local message="$1" expected="$2" inject="$3"
  git reset -q --hard v1.0.0
  printf '{ "branches": ["%s"], "plugins": ["@semantic-release/commit-analyzer"] }' "$branch" > .releaserc
  echo "$RANDOM" > f.txt
  git add f.txt .releaserc
  git commit -q -m "$message"
  git push -q --force origin "$branch" >/dev/null 2>&1
  [[ "$inject" == "yes" ]] && bash "$work/inject.sh" >/dev/null

  local raw actual
  # Strip the ambient Actions environment: semantic-release's CI detection reads
  # GITHUB_REF and would otherwise analyse refs/pull/N/merge, not this fixture.
  raw="$(env -u GITHUB_REF -u GITHUB_ACTIONS -u GITHUB_EVENT_NAME -u GITHUB_HEAD_REF \
           -u GITHUB_BASE_REF -u GITHUB_REPOSITORY -u CI \
           npx --yes semantic-release@25.0.3 --dry-run --no-ci --branches "$branch" 2>&1 || true)"
  actual="$(printf '%s' "$raw" | grep -oiE 'major release|minor release|patch release|no release' | head -1 || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "bump mismatch for '${message%%$'\n'*}' (inject=$inject): expected '$expected', got '${actual:-<none>}'" >&2
    printf '%s\n' "$raw" | grep -vE '^\s*at |node_modules' | tail -25 >&2
    exit 1
  fi
  printf '  inject=%-4s %-42s -> %s\n' "$inject" "${message%%$'\n'*}" "$actual"
}

# The regression: without the option, bang commits release NOTHING.
assert_bump "feat!: breaking"              "no release"    "no"
# With it, every bang form is a major.
assert_bump "feat!: breaking"              "major release" "yes"
assert_bump "fix!: breaking"               "major release" "yes"
assert_bump "feat(scope)!: breaking"       "major release" "yes"
assert_bump "feat(api/client)!: breaking"  "major release" "yes"
# Nothing else may move.
assert_bump "feat: a feature"              "minor release" "yes"
assert_bump "fix: a fix"                   "patch release" "yes"
assert_bump "docs: docs"                   "no release"    "yes"
assert_bump "chore: chore"                 "no release"    "yes"
assert_bump "ci: ci"                       "no release"    "yes"
assert_bump "feat: footer

BREAKING CHANGE: gone."                    "major release" "yes"

echo "✅ bump matrix is correct"
