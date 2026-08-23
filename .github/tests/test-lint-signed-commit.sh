#!/usr/bin/env bash

# lint.yaml's apply-fixes job writes to contributors' pull request branches. Those commits
# must be SIGNED, which means they have to be created through the GitHub commit API with an
# App token -- a `git commit` on a runner cannot be signed, and an unsigned automation commit
# is what keeps signature enforcement from being extendable past the default branch
# (devantler-tech/.github#142).
#
# The workflow proves this at runtime by reading the new commit's own verification object.
# This script is the STATIC half: it fails if the job is ever reshaped back into a CLI commit,
# loses that runtime proof, or loses the branch/credential properties the API commit depends
# on. A runtime proof alone cannot catch a change that stops reaching it.

set -euo pipefail

lint_workflow="${1:-.github/workflows/lint.yaml}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

job='.jobs["apply-fixes"]'

# The whole run block of the job, as one string, so the assertions below read it directly
# rather than guessing which step carries what.
run_block="$(yq -r "[${job}.steps[].run // \"\"] | join(\"\n\")" "$lint_workflow")"
[[ -n "$run_block" ]] ||
  fail "apply-fixes has no run steps at all; this guard is not reading the job it thinks it is"

# 1. The commit is created through the commit API, not by the git CLI.
grep -q 'createCommitOnBranch' <<<"$run_block" ||
  fail "apply-fixes must create its commit with the createCommitOnBranch API (a git CLI commit cannot be signed)"

# 2. No step delegates the commit to a CLI-committing action. Checked against `uses:` rather
#    than the whole file so a comment naming one of these cannot mask a real regression.
cli_commit_actions="$(
  yq -r "[${job}.steps[] | (.uses // \"\")
    | select(test(\"git-auto-commit-action|add-and-commit|git-commit-and-push\"))] | length" \
    "$lint_workflow"
)"
[[ "$cli_commit_actions" == "0" ]] ||
  fail "apply-fixes must not delegate committing to a CLI-committing action; those commits are unsigned"

# 3. The signature is proven at runtime, against the commit's own verification object.
#    Asserting the API call alone would not catch the API silently returning an unsigned
#    commit, which is the failure this whole change exists to prevent.
grep -q 'commit.verification.verified' <<<"$run_block" ||
  fail "apply-fixes must verify the created commit reports verified=true, not assume the API signed it"

# 4. The job checks out the pull request BRANCH. expectedHeadOid is resolved from the checked
#    out HEAD, so a default (merge ref) checkout would pin the mutation to a commit that
#    exists on no branch, and the patch would be applied to the wrong tree.
head_ref_checkouts="$(
  yq -r "[${job}.steps[]
    | select((.uses // \"\") | contains(\"actions/checkout@\"))
    | select((.with.ref // \"\") | test(\"github\\\\.head_ref\"))] | length" \
    "$lint_workflow"
)"
[[ "$head_ref_checkouts" == "1" ]] ||
  fail "apply-fixes must check out github.head_ref (found ${head_ref_checkouts} such checkouts)"

# 5. Nothing persists a write-scoped credential into .git/config. The API commit needs no
#    git push, so a persisted token would be a standing credential with no use.
persisted="$(
  yq -r "[${job}.steps[]
    | select((.uses // \"\") | contains(\"actions/checkout@\"))
    | select(.with.\"persist-credentials\" != false)] | length" \
    "$lint_workflow"
)"
[[ "$persisted" == "0" ]] ||
  fail "every checkout in apply-fixes must set persist-credentials: false; the API commit needs no git credentials"

echo "PASS: applied linter fixes are committed through the signing commit API, and the signature is proven at runtime"
