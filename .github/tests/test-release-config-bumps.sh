#!/usr/bin/env bash
#
# Guards the shared semantic-release config (.github/release-config/) by
# asserting the BUMP it actually produces, not the config's shape.
#
# Shape assertions would not have caught the bug this config exists to fix: a
# bare configuration silently gave `feat!:` NO RELEASE AT ALL, so a breaking
# change shipped unversioned. The config looked perfectly fine. Only running
# semantic-release against real commits reveals it.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
config_dir="$repo_root/.github/release-config"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/node_modules/@devantler-tech/release-config"
cp "$config_dir"/*.json "$work/node_modules/@devantler-tech/release-config/"

# A throwaway repo tagged at its base commit, so ONLY the commit under test is
# ever analysed. (Without this, commits already on the branch since the last tag
# contaminate the result and every case reads the same.)
fixture="$work/fixture"
mkdir -p "$fixture" && cd "$fixture"
git init -q .
git config user.email ci@example.com
git config user.name ci
git config commit.gpgsign false
git init -q --bare "$work/origin.git"
git remote add origin "$work/origin.git"
printf 'node_modules\n' > .gitignore
# npm needs a package.json present or it installs nothing into node_modules.
npm init -y >/dev/null 2>&1
echo base > f.txt
git add f.txt .gitignore package.json
git commit -q -m "chore: base"
git tag v1.0.0
git push -q origin main --tags 2>/dev/null || git push -q origin master --tags

npm install --silent --no-audit --no-fund "semantic-release@25.0.3" >/dev/null 2>&1
if [[ ! -x node_modules/.bin/semantic-release ]]; then
  echo "semantic-release was not installed into the fixture — cannot verify bumps" >&2
  exit 1
fi
cp -R "$work/node_modules/@devantler-tech" node_modules/

branch="$(git rev-parse --abbrev-ref HEAD)"
assert_bump() {
  local message="$1" expected="$2"
  git reset -q --hard v1.0.0
  printf '{ "extends": "@devantler-tech/release-config/tag-only.json", "branches": ["%s"] }' "$branch" > .releaserc
  echo "$RANDOM" > f.txt
  git add f.txt .releaserc
  git commit -q -m "$message"
  git push -q --force origin "$branch" >/dev/null 2>&1
  local raw actual
  raw="$(npx semantic-release --dry-run --no-ci --branches "$branch" 2>&1 || true)"
  actual="$(printf '%s' "$raw" | grep -oiE 'major release|minor release|patch release|no release' | head -1 || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "bump mismatch for '${message%%$'\n'*}': expected '$expected', got '${actual:-<none>}'" >&2
    echo "--- semantic-release output ------------------------------------------" >&2
    printf '%s\n' "$raw" | grep -vE '^\s*at |node_modules' | tail -30 >&2
    echo "----------------------------------------------------------------------" >&2
    exit 1
  fi
  printf '  %-42s -> %s\n' "${message%%$'\n'*}" "$actual"
}

# The bang forms are the regression this config exists to fix.
assert_bump "feat!: breaking"                 "major release"
assert_bump "fix!: breaking"                  "major release"
assert_bump "feat(scope)!: breaking"          "major release"
# A scope containing characters beyond [\w.-] — the default conventional parser
# accepts these, so the bang pattern must not be narrower than it.
assert_bump "feat(api/client)!: breaking"     "major release"
# Everything else must be untouched by that fix.
assert_bump "feat: a feature"                 "minor release"
assert_bump "fix: a fix"                      "patch release"
assert_bump "docs: docs"                      "no release"
assert_bump "chore: chore"                    "no release"
assert_bump "ci: ci"                          "no release"
assert_bump "feat: footer

BREAKING CHANGE: gone."                       "major release"

echo "✅ bump matrix is correct"
