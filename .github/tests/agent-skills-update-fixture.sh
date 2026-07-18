#!/usr/bin/env bash
# Contract test for the update-agent-skills CI fixture. Update tests must not
# call setup-agent-skills merely to prepare their input: that adds redundant
# live GitHub API traffic to the rate-limit burst tracked by actions#514.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflow="$repo_root/.github/workflows/ci.yaml"
fixture_rel=".github/tests/agent-skills-fixtures/pinned-self-improvement"
fixture="$repo_root/$fixture_rel/SKILL.md"

fail() {
  echo "::error::$*"
  exit 1
}

for job in test-update-agent-skills-noop test-update-agent-skills-dry-run; do
  setup_steps=$(yq -r ".jobs.\"$job\".steps // [] | map(select(.uses == \"./setup-agent-skills\")) | length" "$workflow")
  if [[ "$setup_steps" != "0" ]]; then
    fail "$job must seed its deterministic fixture without setup-agent-skills (got $setup_steps setup step(s))"
  fi

  update_steps=$(yq -r ".jobs.\"$job\".steps // [] | map(select(.uses == \"./update-agent-skills\")) | length" "$workflow")
  if [[ "$update_steps" != "1" ]]; then
    fail "$job must keep exactly one real update-agent-skills invocation (got $update_steps)"
  fi

  seed_script=$(yq -r ".jobs.\"$job\".steps[] | select(.name == \"📦 Seed pinned agent-skill fixture\") | .run" "$workflow")
  if [[ "$seed_script" != *"$fixture_rel"* || "$seed_script" != *".agents/skills/self-improvement"* ]]; then
    fail "$job must copy $fixture_rel into .agents/skills/self-improvement"
  fi
done

noop_oses=$(yq -r '.jobs."test-update-agent-skills-noop".strategy.matrix.os | join(",")' "$workflow")
if [[ "$noop_oses" != "ubuntu-latest,macos-latest" ]]; then
  fail "update no-op coverage must remain on Ubuntu and macOS (got $noop_oses)"
fi

setup_oses=$(yq -r '.jobs."test-setup-agent-skills-inline".strategy.matrix.os | join(",")' "$workflow")
if [[ "$setup_oses" != "ubuntu-latest,macos-latest" ]]; then
  fail "real setup-agent-skills coverage must remain on Ubuntu and macOS (got $setup_oses)"
fi

for job in test-setup-agent-skills-inline test-setup-agent-skills-pinned test-setup-agent-skills-multi-agent; do
  setup_steps=$(yq -r ".jobs.\"$job\".steps // [] | map(select(.uses == \"./setup-agent-skills\")) | length" "$workflow")
  if [[ "$setup_steps" != "1" ]]; then
    fail "$job must retain its real setup-agent-skills invocation (got $setup_steps)"
  fi
done

[[ -f "$fixture" ]] || fail "missing pinned agent-skill fixture: $fixture_rel/SKILL.md"

expected_ref="7b9904e7a2739f2ecdea621c5bc548804bddb9c2"
expected_tree="d3e05d9dd8bdb03e7bd65f7b2b6ca30efba53ad2"
grep -q '^    github-repo: https://github.com/devantler-tech/agent-skills$' "$fixture" ||
  fail "fixture github-repo metadata must point to devantler-tech/agent-skills"
grep -q '^    github-path: self-improvement$' "$fixture" ||
  fail "fixture github-path metadata must identify self-improvement"
grep -q "^    github-ref: $expected_ref$" "$fixture" ||
  fail "fixture github-ref must stay pinned to $expected_ref"
grep -q "^    github-pinned: $expected_ref$" "$fixture" ||
  fail "fixture github-pinned metadata must preserve the explicit pin to $expected_ref"
grep -q "^    github-tree-sha: $expected_tree$" "$fixture" ||
  fail "fixture github-tree-sha must stay pinned to $expected_tree"

noop_verify=$(yq -r '.jobs."test-update-agent-skills-noop".steps[] | select(.name == "✅ Verify pinned no-op") | .run' "$workflow")
if [[ "$noop_verify" != *"UPDATED"* || "$noop_verify" != *"is pinned to"* || "$noop_verify" != *"self-improvement"* ]]; then
  fail "pinned no-op verification must assert the CLI skipped self-improvement because it is pinned"
fi

dry_run_unpin=$(yq -r '.jobs."test-update-agent-skills-dry-run".steps[] | select(.uses == "./update-agent-skills") | .with.unpin' "$workflow")
dry_run_mode=$(yq -r '.jobs."test-update-agent-skills-dry-run".steps[] | select(.uses == "./update-agent-skills") | .with."dry-run"' "$workflow")
if [[ "$dry_run_unpin" != "true" || "$dry_run_mode" != "true" ]]; then
  fail "dry-run job must pass both unpin=true and dry-run=true to update-agent-skills"
fi

dry_run_verify=$(yq -r '.jobs."test-update-agent-skills-dry-run".steps[] | select(.name == "✅ Verify pending update without mutation") | .run' "$workflow")
if [[ "$dry_run_verify" != *"UPDATED"* || "$dry_run_verify" != *"update(s) available"* || "$dry_run_verify" != *"self-improvement"* ]]; then
  fail "unpin dry-run verification must assert a pending self-improvement update was reported"
fi

echo "all agent-skills update-fixture checks passed"
