#!/usr/bin/env bash
# Execute the shipped guard against consumer files, without running semantic-release.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workflow="$repo_root/.github/workflows/create-release.yaml"
ci="$repo_root/.github/workflows/ci.yaml"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq -r '.jobs.release.steps[] | select(.id == "breaking-bang-guard") | .run' "$workflow" >"$tmp/guard.sh"

missing='{"plugins":[["@semantic-release/commit-analyzer",{"releaseRules":[{"type":"ci","release":"patch"}]}]]}'
configured='{"plugins":[["@semantic-release/commit-analyzer",{"parserOpts":{"breakingHeaderPattern":"^.*!:","headerPattern":"^.*:"},"releaseRules":[{"breaking":true,"release":"major"}]}]]}'
cases=0

check() {
  local name="$1" expected="$2" output before after
  shift 2
  mkdir "$tmp/$name"
  while (( $# )); do
    printf '%s' "$2" >"$tmp/$name/$1"
    shift 2
  done
  before="$(cd "$tmp/$name" && find . -type f -exec shasum {} \; | sort)"
  output="$(cd "$tmp/$name" && bash -euo pipefail "$tmp/guard.sh" 2>&1)" || {
    echo "FAIL $name: guard must never stop a release: $output" >&2
    exit 1
  }
  if [[ "$expected" == warning ]]; then
    if [[ "$output" != ::warning::*breakingHeaderPattern* ]]; then
      echo "FAIL $name: expected actionable warning, got: $output" >&2
      exit 1
    fi
    [[ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" == 1 ]]
  elif [[ -n "$output" ]]; then
    echo "FAIL $name: unsupported/configured consumer must stay silent: $output" >&2
    exit 1
  fi
  after="$(cd "$tmp/$name" && find . -type f -exec shasum {} \; | sort)"
  [[ "$before" == "$after" ]] || { echo "FAIL $name: changed consumer files" >&2; exit 1; }
  cases=$((cases + 1))
}

check lost-parser warning .releaserc "$missing"
check json-extension warning .releaserc.json "$missing"
check package-release warning package.json "{\"release\":$missing}"
check healthy silent .releaserc "$configured"
check healthy-package silent package.json "{\"release\":$configured}"
check explicit-plugin warning .releaserc '{"plugins":["@semantic-release/commit-analyzer"]}'
check empty-parser warning .releaserc '{"plugins":[["@semantic-release/commit-analyzer",{"parserOpts":{"breakingHeaderPattern":""}}]]}'
check no-config silent
check default-plugins silent .releaserc '{"branches":["main"]}'
check unrelated-plugin silent .releaserc '{"plugins":["@semantic-release/github"]}'
check package-without-release warning package.json '{"name":"consumer"}' .releaserc "$missing"
check global-parser silent .releaserc '{"parserOpts":{"breakingHeaderPattern":"^.*!:"},"plugins":["@semantic-release/commit-analyzer"]}'
check conventional-commits silent .releaserc '{"plugins":[["@semantic-release/commit-analyzer",{"preset":"conventionalcommits"}]]}'
check custom-preset silent .releaserc '{"plugins":[["@semantic-release/commit-analyzer",{"preset":"custom"}]]}'
check global-preset silent .releaserc '{"preset":"custom","plugins":["@semantic-release/commit-analyzer"]}'
check custom-parser silent .releaserc '{"plugins":[["@semantic-release/commit-analyzer",{"config":"./parser.cjs"}]]}'
check shared-config silent .releaserc '{"extends":"shared-release-config","plugins":["@semantic-release/commit-analyzer"]}'
check yaml silent .releaserc 'plugins: ["@semantic-release/commit-analyzer"]'
check malformed silent .releaserc '{ broken'
check multiple-documents silent .releaserc "{} $missing"
check malformed-package silent package.json '{ broken' .releaserc "$missing"
check unsupported-shape silent .releaserc '["@semantic-release/commit-analyzer"]'
check malformed-plugin silent .releaserc '{"plugins":[["@semantic-release/commit-analyzer",false]]}'
check ambiguous-json silent .releaserc "$configured" .releaserc.json "$missing"
check ambiguous-package silent package.json "{\"release\":$configured}" .releaserc "$missing"
for name in .releaserc.yml .releaserc.yaml .releaserc.js .releaserc.cjs .releaserc.mjs .releaserc.ts .releaserc.cts release.config.js release.config.cjs release.config.mjs release.config.ts release.config.cts; do
  check "unsupported-$name" silent "$name" 'throw new Error("must not execute config")' .releaserc "$missing"
done

# The workflow boundary matters: disabled callers never execute the guard, and
# even an unexpected tool failure cannot keep semantic-release from running.
yq -o=json '.' "$workflow" | jq -e '.on.workflow_call.inputs."warn-missing-breaking-bang" | .default == false and .type == "boolean"' >/dev/null
# shellcheck disable=SC2016 # The GitHub expression is deliberately literal.
yq -o=json '.' "$workflow" | jq -e '.jobs.release.steps[] | select(.id == "breaking-bang-guard") | .if == "${{ inputs.warn-missing-breaking-bang }}" and ."continue-on-error" == true and .shell == "bash"' >/dev/null
yq -e '.jobs."test-create-release".with | has("warn-missing-breaking-bang") == false' "$ci" >/dev/null
yq -e '.jobs."test-create-release-no-issue-side-effects".with."warn-missing-breaking-bang" == true' "$ci" >/dev/null
echo "$cases consumer fixtures passed; guard is read-only, opt-in and non-blocking"
