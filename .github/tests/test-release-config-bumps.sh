#!/usr/bin/env bash
#
# Guards the shared semantic-release config on two axes:
#
#   1. DRIFT — the heredoc embedded in create-release.yaml must stay
#      byte-identical to the reviewable copies in release-config/.
#   2. BEHAVIOUR — the config must actually map commit types to the intended
#      bumps. This is the check that was missing when a bare configuration
#      silently gave `feat!:` NO RELEASE AT ALL (a breaking change shipping
#      unversioned), so it asserts the real bump, not the config's shape.

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workflow="$repo_root/.github/workflows/create-release.yaml"
config_dir="$repo_root/release-config"

# --- 1. drift -----------------------------------------------------------------
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

yq -r '.jobs.release.steps[] | select(.name | test("Materialise")) | .run' "$workflow" > "$work/materialise.sh"
( cd "$work" && bash materialise.sh >/dev/null )

for f in package.json index.json tag-only.json; do
  if ! diff -q "$config_dir/$f" "$work/node_modules/@devantler-tech/release-config/$f" >/dev/null; then
    echo "release-config/$f has drifted from the heredoc in create-release.yaml" >&2
    diff -u "$config_dir/$f" "$work/node_modules/@devantler-tech/release-config/$f" >&2 || true
    exit 1
  fi
done
echo "✅ embedded config is byte-identical to release-config/"

# --- 2. behaviour -------------------------------------------------------------
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
  local actual
  actual="$(npx semantic-release --dry-run --no-ci --branches "$branch" 2>&1 \
    | grep -oiE 'major release|minor release|patch release|no release' | head -1 || true)"
  if [[ "$actual" != "$expected" ]]; then
    echo "bump mismatch for '${message%%$'\n'*}': expected '$expected', got '${actual:-<none>}'" >&2
    exit 1
  fi
  printf '  %-42s -> %s\n' "${message%%$'\n'*}" "$actual"
}

# The bang forms are the regression this config exists to fix.
assert_bump "feat!: breaking"                 "major release"
assert_bump "fix!: breaking"                  "major release"
assert_bump "feat(scope)!: breaking"          "major release"
# Everything else must be untouched by that fix.
assert_bump "feat: a feature"                 "minor release"
assert_bump "fix: a fix"                      "patch release"
assert_bump "docs: docs"                      "no release"
assert_bump "chore: chore"                    "no release"
assert_bump "ci: ci"                          "no release"
assert_bump "feat: footer

BREAKING CHANGE: gone."                       "major release"

echo "✅ bump matrix is correct"
