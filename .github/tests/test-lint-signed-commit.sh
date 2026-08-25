#!/usr/bin/env bash

# Applied linter fixes are written to contributors' pull request branches. Those commits must
# be SIGNED, which means they have to be created through the GitHub commit API with an App
# token -- a `git commit` on a runner cannot be signed, and an unsigned automation commit is
# what keeps signature enforcement from being extendable past the default branch
# (devantler-tech/.github#142).
#
# The commit itself lives in apply-signed-fixes.yaml so every fixer lane shares one signed
# implementation. That workflow proves the signature at runtime by reading the new commit's own
# verification object. This script is the STATIC half, and it guards BOTH halves of the split:
# that the caller still delegates to that workflow rather than committing for itself, and that
# the workflow still commits the signing way. A runtime proof alone cannot catch a change that
# stops reaching it, and an assertion aimed only at the callee cannot catch a caller that
# stopped calling it.

set -euo pipefail

caller_workflow="${1:-.github/workflows/lint.yaml}"
signer_workflow="${2:-.github/workflows/apply-signed-fixes.yaml}"
consumer_relative_signer="./${signer_workflow#./}"
workflow_source_signer="\$/${signer_workflow#./}"
immutable_source_signer_re="^devantler-tech/actions/${signer_workflow#./}@[0-9a-f]{40}$"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

is_signer_ref() {
  local candidate="$1"
  [[ "$candidate" == "$consumer_relative_signer" ||
    "$candidate" == "$workflow_source_signer" ||
    "$candidate" =~ $immutable_source_signer_re ]]
}

# Prove assertion 1b fails closed when its yq projection fails. The wrapper
# delegates every other query to the real binary and fails only the
# inline-commit projection below. Without this probe,
# `|| true` on that projection's pipeline can convert the yq failure into a
# zero grep count and let the whole guard print PASS.
if [[ "${LINT_SIGNED_COMMIT_YQ_FAILURE_PROBE:-0}" != "1" ]]; then
  real_yq="$(command -v yq)"
  probe_dir="$(mktemp -d)"
  cat >"${probe_dir}/yq" <<'YQ_PROBE'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" != *'[.jobs[].steps[]? | (.run // "")] | join("\n")'* ]] || exit 42
exec "${REAL_YQ}" "$@"
YQ_PROBE
  chmod +x "${probe_dir}/yq"
  if env LINT_SIGNED_COMMIT_YQ_FAILURE_PROBE=1 REAL_YQ="${real_yq}" \
    PATH="${probe_dir}:${PATH}" bash "$0" "${caller_workflow}" \
    "${signer_workflow}" >/dev/null 2>&1; then
    rm -rf "${probe_dir}"
    fail 'the inline-commit assertion passed when its yq projection failed'
  fi
  rm -rf "${probe_dir}"
fi

bot_suppression='dependabot\[bot\]'

# ── The caller delegates, and commits nothing itself ─────────────────────────────────────

# 0. The apply-fixes job hands the commit to the shared signing workflow. Without this, the
#    assertions below would keep passing against an apply-signed-fixes.yaml that nothing calls.
delegated="$(yq -r '.jobs["apply-fixes"].uses // ""' "$caller_workflow")"
is_signer_ref "$delegated" ||
  fail "${caller_workflow}'s apply-fixes job must use an exact local signer or the immutable source-repository signer (found '${delegated:-nothing}')"

# 1. No job anywhere in the caller delegates a commit to a CLI-committing action. Scoped to the
#    whole file, not just apply-fixes: re-adding such a step to the lint job would put unsigned
#    commits back on the branch by another route.
caller_cli_commits="$(
  yq -r "[.jobs[].steps[]? | (.uses // \"\")
    | select(test(\"git-auto-commit-action|add-and-commit|git-commit-and-push\"))] | length" \
    "$caller_workflow"
)"
[[ "$caller_cli_commits" == "0" ]] ||
  fail "${caller_workflow} must not commit with a CLI-committing action; those commits are unsigned"

# 1b. No job anywhere in the caller commits inline either. Assertion 1 knows only the NAMED
#     CLI-committing actions, and assertion 0 is scoped to the single `apply-fixes` job — so a
#     lane that stops delegating and inlines `run: git commit && git push` is caught by neither.
#     That matters most in validate-go-project.yaml, which carries THREE apply lanes
#     (apply-tidy-fixes, apply-golangci-lint-fixes, apply-fixes): two of them are invisible to
#     assertion 0, and one left committing by hand would put unsigned commits back on
#     contributors' branches while this guard stayed green.
#     Read verbs, not the word `git`: the fork gates legitimately run `git status`/`git diff`.
caller_run_blocks="$(yq -r '[.jobs[].steps[]? | (.run // "")] | join("\n")' "$caller_workflow")"
#     Match the SUBCOMMAND, not the token right after `git`. Git accepts global options before the
#     subcommand, and a command may sit inside a substitution, so a pattern requiring `git`
#     immediately followed by the verb misses `git -C "$GITHUB_WORKSPACE" commit`,
#     `git --no-pager push` and `$(git commit …)`. This is a SECURITY assertion: each miss is an
#     unsigned commit reaching a contributor's branch while the guard reports zero and stays green.
#     Git's global options are a closed, documented set, so they can be consumed exactly — which
#     keeps `git status`/`git diff` in the fork gates unmatched, rather than skipping arbitrary
#     tokens and turning legitimate reads into failures.
git_global_opt='(-[Cc][[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path)[=[:space:]][^[:space:]]+|--no-pager|--paginate|-P|--bare|--(literal|glob|noglob|icase)-pathspecs|--no-optional-locks|--no-replace-objects)'
#     Leading class admits a substitution opener; trailing class admits a substitution closer, so
#     `$(git commit)` and `` `git push` `` are both bounded correctly.
git_inline_commit_re='(^|[;&|(`[:space:]])git([[:space:]]+'"$git_global_opt"')*[[:space:]]+(commit|push)([[:space:];&|)`]|$)'
caller_inline_commits="$(
  grep -cE "$git_inline_commit_re" <<<"$caller_run_blocks" || true
)"
[[ "$caller_inline_commits" == "0" ]] ||
  fail "${caller_workflow} must not run 'git commit' or 'git push' in any job; those commits are unsigned — delegate to ./${signer_workflow#./} instead"

# 1c. …and the delegation the whole file depends on is not vacuous: at least one job must
#     actually call the signer, or every assertion below is about a workflow nothing reaches.
caller_uses="$(yq -r '[.jobs[] | (.uses // "")] | .[]' "$caller_workflow")"
caller_delegations=0
while IFS= read -r caller_use; do
  if is_signer_ref "$caller_use"; then
    caller_delegations=$((caller_delegations + 1))
  fi
done <<<"$caller_uses"
[[ "$caller_delegations" -gt 0 ]] ||
  fail "${caller_workflow} has no job delegating to an exact local or immutable source-repository signer; this guard would assert nothing"

# ── The shared signing workflow commits the signing way ──────────────────────────────────

job='.jobs["apply-fixes"]'

# The whole run block of the job, as one string, so the assertions below read it directly
# rather than guessing which step carries what.
run_block="$(yq -r "[${job}.steps[].run // \"\"] | join(\"\n\")" "$signer_workflow")"
[[ -n "$run_block" ]] ||
  fail "apply-fixes has no run steps at all; this guard is not reading the job it thinks it is"

# 2. The commit is created through the commit API, not by the git CLI. Matched on the
#    mutation call itself, not the bare name: the run block also carries diagnostics like
#    `::error::createCommitOnBranch failed`, so a bare-name match would still pass if the
#    mutation were removed and only its error handling left behind.
grep -q 'createCommitOnBranch(input:' <<<"$run_block" ||
  fail "apply-fixes must create its commit with the createCommitOnBranch API (a git CLI commit cannot be signed)"

# 3. No step delegates the commit to a CLI-committing action. Checked against `uses:` rather
#    than the whole file so a comment naming one of these cannot mask a real regression.
cli_commit_actions="$(
  yq -r "[${job}.steps[] | (.uses // \"\")
    | select(test(\"git-auto-commit-action|add-and-commit|git-commit-and-push\"))] | length" \
    "$signer_workflow"
)"
[[ "$cli_commit_actions" == "0" ]] ||
  fail "apply-fixes must not delegate committing to a CLI-committing action; those commits are unsigned"

# 4. The signature is proven at runtime, against the commit's own verification object.
#    Asserting the API call alone would not catch the API silently returning an unsigned
#    commit, which is the failure this whole change exists to prevent.
grep -q 'commit.verification.verified' <<<"$run_block" ||
  fail "apply-fixes must verify the created commit reports verified=true, not assume the API signed it"

# 5. The job checks out the pull request BRANCH. expectedHeadOid is resolved from the checked
#    out HEAD, so a default (merge ref) checkout would pin the mutation to a commit that
#    exists on no branch, and the patch would be applied to the wrong tree.
head_ref_checkouts="$(
  yq -r "[${job}.steps[]
    | select((.uses // \"\") | contains(\"actions/checkout@\"))
    | select((.with.ref // \"\") | test(\"github\\\\.head_ref\"))] | length" \
    "$signer_workflow"
)"
[[ "$head_ref_checkouts" == "1" ]] ||
  fail "apply-fixes must check out github.head_ref (found ${head_ref_checkouts} such checkouts)"

# 6. Nothing persists a write-scoped credential into .git/config. The API commit needs no
#    git push, so a persisted token would be a standing credential with no use.
persisted="$(
  yq -r "[${job}.steps[]
    | select((.uses // \"\") | contains(\"actions/checkout@\"))
    | select(.with.\"persist-credentials\" != false)] | length" \
    "$signer_workflow"
)"
[[ "$persisted" == "0" ]] ||
  fail "every checkout in apply-fixes must set persist-credentials: false; the API commit needs no git credentials"

# 7. The dependency-bot suppression lives with the commit, not only in the caller. A bot's
#    branch is owned by its automation, and this gate moved here when the commit did, so a
#    future caller cannot omit it by forgetting to copy a condition.
job_if="$(yq -r "${job}.if // \"\"" "$signer_workflow")"
grep -qE "$bot_suppression" <<<"$job_if" ||
  fail "apply-fixes must itself suppress dependency-bot pull requests; their branches are owned by their automation"

# 8. The pull-request event predicate moved here with the other gates, and lint.yaml no longer
#    supplies it. Without this assertion a later edit could let a caller reach the signing job on a
#    non-pull_request event, where github.head_ref is empty -- so the checkout and expectedHeadOid
#    would resolve against nothing, and the branch the commit targets would not be the one under
#    review.
grep -q "github.event_name == 'pull_request'" <<<"$job_if" ||
  fail "apply-fixes must itself require a pull_request event; lint.yaml no longer supplies that gate"

# 9. Fork pull requests never reach the commit. They get no secrets, so the App token cannot be
#    minted; committing there could only fail, and the caller lints them read-only instead.
grep -q 'head.repo.fork' <<<"$job_if" ||
  fail "apply-fixes must itself refuse fork pull requests, which cannot mint the App token"

# 10. Assertions 7-9 each check that one predicate is PRESENT, which cannot see a predicate that
#     was ADDED. A fifth conjunct suppressing every eligible pull request -- a stray `&& false`,
#     an author allowlist, a branch-name filter -- leaves all three green while the workflow
#     silently stops committing anything, and the suppression self-test in ci.yaml cannot catch it
#     either, because that test asserts a bot input is REFUSED and a dead gate refuses it too.
#     There is no passes-on-good-input runtime test to fall back on: committing to the branch
#     under test is exactly what a self-test must not do (the reasoned gap recorded in ci.yaml).
#     So the gate is whitelisted rather than spot-checked -- the conjunct count is pinned, and a
#     new predicate has to come here and be justified instead of landing silently.
conjuncts="$(grep -o '&&' <<<"$job_if" | wc -l | tr -d ' ')"
[[ "$conjuncts" == "3" ]] ||
  fail "apply-fixes' if: must carry exactly the 4 audited conjuncts (pull_request, non-fork, non-bot author, non-bot pr-owner), found $((conjuncts + 1)); a predicate added here can suppress every eligible pull request while assertions 7-9 stay green"


# ── The job executes nothing from the checked-out tree ───────────────────────────────────

# CodeQL alert 312 (actions/untrusted-checkout/medium) on this workflow was dismissed as a
# false positive during review of #1011, and that dismissal rests entirely on one property:
# no step in apply-fixes executes code from the checked-out repository. The job checks out the
# pull request's head branch and holds an App token scoped `contents: write`, so the property
# is the whole reason that combination is safe. Dismissal is per-alert rather than
# per-condition, so the alert does NOT re-fire when the property stops holding -- a build step,
# an `npm ci`, or a local action would simply land green. Assertions 11 and 12 are what stop
# that, and they are whitelists for the reason assertion 10 gives: a blacklist of forbidden
# spellings is out-run by the next spelling.

# 11. Every `uses:` is a SHA-pinned action from an audited identity. Both axes matter and they
#     fail differently: an unpinned or local ref (`uses: ./...`) runs a definition out of the
#     untrusted tree, which is exactly the shape the alert was raised for, while a tag or
#     branch ref lets an audited identity's contents change with no edit here at all.
audited_actions=$'step-security/harden-runner\nactions/create-github-app-token\nactions/checkout\nactions/download-artifact'
# Captured rather than piped from a process substitution: a yq failure inside `< <(...)` is
# invisible to both `set -e` and `pipefail`, so it would read as an empty step list and this
# assertion would pass having checked nothing.
step_uses_list="$(yq -r "[${job}.steps[] | .uses // \"\"] | .[]" "$signer_workflow")"
# An empty projection would run the loop zero times and report PASS having checked nothing --
# the same vacuous-success shape the yq failure probe at the top of this file guards against.
[[ -n "$step_uses_list" ]] ||
  fail "apply-fixes yielded no steps to check; this assertion is not reading the job it thinks it is"
while IFS= read -r step_uses; do
  [[ -n "$step_uses" ]] || continue
  [[ "$step_uses" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+(/[^@]+)?@[0-9a-f]{40}$ ]] ||
    fail "apply-fixes step 'uses: ${step_uses}' must be a SHA-pinned action reference; a local 'uses: ./...' executes an action definition from the checked-out tree, and a tag or branch ref can change under the pin"
  grep -qxF -- "${step_uses%%@*}" <<<"$audited_actions" ||
    fail "apply-fixes uses the unaudited action '${step_uses%%@*}'; add it to audited_actions here only after confirming it executes nothing from the checked-out tree"
done <<<"$step_uses_list"

# 12. The step inventory is pinned: how many steps there are, and whether each one is a `uses:`
#     or a `run:`, in order. This is the load-bearing half. Assertion 11 can only judge steps
#     that declare a `uses:`, so on its own it cannot see a `run: npm ci` appended to the job --
#     the step inventory can, because the count changes whatever the new step is spelled like.
#     Pinning the shape rather than the step NAMES is deliberate: #1048 records an exact-spelling
#     match in this same guard breaking on a reformat, and a name is prose that gets reworded.
#     A step carrying BOTH `uses:` and `run:` is not valid workflow syntax and is reported rather
#     than silently classified as one of them.
step_shape="$(
  yq -r "[${job}.steps[] | (((.uses // \"\") | length > 0) | tostring) + \":\" + (((.run // \"\") | length > 0) | tostring)] | join(\",\")" \
    "$signer_workflow" |
    sed -e 's/true:false/uses/g' -e 's/false:true/run/g' \
      -e 's/true:true/uses+run/g' -e 's/false:false/empty/g'
)"
[[ "$step_shape" == "uses,run,uses,uses,uses,run,run" ]] ||
  fail "apply-fixes' step inventory changed (found '${step_shape}', audited 'uses,run,uses,uses,uses,run,run'); a step added or retyped here can execute checked-out code, which is the premise CodeQL alert 312 was dismissed on -- re-audit the job and update this pin deliberately"

echo "PASS: applied linter fixes are delegated to the signing commit API, and the signature is proven at runtime"
