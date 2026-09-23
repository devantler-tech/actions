#!/usr/bin/env bash

# update-agent-skills.yaml's opt-in per-skill mode (#1309). Consumers (agent-plugins, platform,
# ksail) match the exact `deps/agent-skills-update` branch and title today, so with the flag off
# the workflow must open the same single PR it always has; with it on, one PR per changed skill.
# This pins both states in the workflow and in ci.yaml, and runs the per-skill job's own apply
# step against a real patch so it both accepts its skill and refuses anything outside it.
# test-split-skill-updates.sh covers the splitter that produces those patches.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow="${1:-$repo_root/.github/workflows/update-agent-skills.yaml}"
ci="${2:-$repo_root/.github/workflows/ci.yaml}"
splitter="$repo_root/.github/scripts/split-skill-updates.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

q() { yq -r "$1" "$workflow"; }

# ── the flag ────────────────────────────────────────────────────────────────────────────────
[[ "$(q '.on.workflow_call.inputs.pr-per-skill.type')" == "boolean" ]] ||
  fail "pr-per-skill must be a boolean workflow_call input"
[[ "$(q '.on.workflow_call.inputs.pr-per-skill.default')" == "false" ]] ||
  fail "pr-per-skill must default to false, so existing callers keep their single PR"

# ── flag off: the single PR is unchanged ─────────────────────────────────────────────────────
batch='.jobs.update-agent-skills.steps[] | select(.name == "📦 Create pull request")'
[[ "$(q "[${batch}] | length")" == "1" ]] || fail "the update job must keep exactly one batch PR step"
batch_if="$(q "${batch} | .if")"
grep -qF '!inputs.pr-per-skill' <<<"$batch_if" || fail "the batch PR step must run only with the flag off: ${batch_if}"
grep -qF "steps.update.outputs.changed == 'true'" <<<"$batch_if" ||
  fail "the batch PR step must still run only when a skill changed: ${batch_if}"
# shellcheck disable=SC2016 # GitHub expressions compared as literal text
{
  [[ "$(q "${batch} | .with.branch")" == '${{ inputs.pr-branch }}' ]] || fail "the batch PR must use pr-branch unchanged"
  [[ "$(q "${batch} | .with.title")" == '${{ inputs.pr-title }}' ]] || fail "the batch PR must use pr-title unchanged"
  [[ "$(q "${batch} | .with.commit-message")" == '${{ inputs.commit-message }}' ]] ||
    fail "the batch PR must use commit-message unchanged"
}
[[ "$(q "${batch} | .with.sign-commits")" == "true" ]] || fail "the batch PR must keep sign-commits"
echo "ok: flag off — one PR from pr-branch with the same title, message and signing as before"

# ── flag on: split, then one PR per skill ────────────────────────────────────────────────────
for step in "📋 Keep the per-skill splitter" "🧩 Split the update per skill"; do
  cond="$(q ".jobs.update-agent-skills.steps[] | select(.name == \"$step\") | .if")"
  grep -qF 'inputs.pr-per-skill' <<<"$cond" || fail "'$step' must run only with the flag on: ${cond}"
done
index_of() { q ".jobs.update-agent-skills.steps | to_entries[] | select(.value.name == \"$1\") | .key"; }
(($(index_of "📋 Keep the per-skill splitter") < $(index_of "🧹 Remove self-checkout"))) ||
  fail "the splitter must be copied out before the self-checkout is removed"
(($(index_of "🧹 Remove self-checkout") < $(index_of "🧩 Split the update per skill"))) ||
  fail "the split must run after the self-checkout is removed, or dir '.' would stage it"

job='.jobs.open-skill-pull-requests'
job_if="$(q "${job}.if")"
grep -qF 'inputs.pr-per-skill' <<<"$job_if" || fail "the per-skill job must run only with the flag on: ${job_if}"
[[ "$(q "${job}.needs")" == "update-agent-skills" ]] || fail "the per-skill job must need the update job"
[[ "$(q "${job}.strategy.fail-fast")" == "false" ]] ||
  fail "one skill's failure must not cancel the others (fail-fast: false)"
per_skill='.jobs.open-skill-pull-requests.steps[] | select(.name == "📦 Create pull request")'
# shellcheck disable=SC2016 # GitHub expressions compared as literal text
[[ "$(q "${per_skill} | .with.branch")" == '${{ inputs.pr-branch }}-${{ matrix.skill.slug }}' ]] ||
  fail "each per-skill PR must come from <pr-branch>-<slug>"
[[ "$(q "${per_skill} | .with.sign-commits")" == "true" ]] || fail "per-skill PRs must sign their commits"
echo "ok: flag on — the update is split after the self-checkout is gone, one signed PR per skill"

# ── both states instantiated in ci.yaml ──────────────────────────────────────────────────────
callers="$(yq -r '.jobs[] | select(.uses == "./.github/workflows/update-agent-skills.yaml") | (.with."pr-per-skill" // "omitted")' "$ci" | sort -u | paste -sd, -)"
[[ "$callers" == "omitted,true" ]] ||
  fail "ci.yaml must call update-agent-skills.yaml both without pr-per-skill and with it true (found: ${callers})"
echo "ok: ci.yaml instantiates both flag states"

# ── the apply step accepts its own skill and refuses anything else ───────────────────────────
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
yq -r "${job}.steps[] | select(.name == \"🩹 Apply only this skill's update\") | .run" "$workflow" >"$work/apply.sh"
[[ -s "$work/apply.sh" ]] || fail "the per-skill job has no apply step"

repo="$work/repo"
git init -q -b main "$repo"
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config commit.gpgsign false
mkdir -p "$repo/skills/alpha" "$repo/skills/beta"
printf 'alpha v1\n' >"$repo/skills/alpha/SKILL.md"
printf 'beta v1\n' >"$repo/skills/beta/SKILL.md"
git -C "$repo" add -A
git -C "$repo" commit -q -m base
printf 'alpha v2\n' >"$repo/skills/alpha/SKILL.md"
manifest="$(cd "$repo" && bash "$splitter" skills "$work/patches")"
[[ "$(jq -r '.[0].slug' <<<"$manifest")" == "alpha" ]] || fail "unexpected manifest: ${manifest}"
git -C "$repo" checkout -q -- .

run_apply() {
  (cd "$repo" && RUNNER_TEMP="$work/runner" SKILL_SLUG="$1" SKILL_PATH="$2" bash "$work/apply.sh") 2>&1
}
mkdir -p "$work/runner/skill-updates"
cp "$work/patches/alpha.patch" "$work/runner/skill-updates/alpha.patch"
out="$(run_apply alpha skills/alpha)" || fail "the apply step refused its own skill: ${out}"
[[ "$(cat "$repo/skills/alpha/SKILL.md")" == "alpha v2" ]] || fail "the apply step did not apply the patch"
git -C "$repo" checkout -q -- .
echo "ok: the apply step applies its own skill's patch"

if out="$(run_apply alpha skills/beta)"; then
  fail "the apply step accepted a patch outside its skill"
fi
grep -qF "outside that skill" <<<"$out" || fail "the refusal does not explain itself: ${out}"
git -C "$repo" checkout -q -- .
if out="$(run_apply missing skills/alpha)"; then
  fail "the apply step accepted a missing patch"
fi
echo "ok: the apply step refuses a patch outside its skill and a missing patch"

echo "PASS: update-agent-skills keeps its single PR by default and opens isolated per-skill PRs when opted in"
