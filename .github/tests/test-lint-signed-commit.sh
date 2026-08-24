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

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

bot_suppression='dependabot\[bot\]'

# ── The caller delegates, and commits nothing itself ─────────────────────────────────────

# 0. The apply-fixes job hands the commit to the shared signing workflow. Without this, the
#    assertions below would keep passing against an apply-signed-fixes.yaml that nothing calls.
delegated="$(yq -r '.jobs["apply-fixes"].uses // ""' "$caller_workflow")"
[[ "$delegated" == "./${signer_workflow#./}" ]] ||
  fail "${caller_workflow}'s apply-fixes job must delegate to ./${signer_workflow#./} (found '${delegated:-nothing}')"

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

echo "PASS: applied linter fixes are delegated to the signing commit API, and the signature is proven at runtime"
