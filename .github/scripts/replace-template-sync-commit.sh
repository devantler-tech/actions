#!/usr/bin/env bash

set -euo pipefail

fail() {
  echo "template-sync signing: $*" >&2
  exit 1
}

usage() {
  echo "usage: $0 --base-sha <sha> --branch-prefix <prefix>" >&2
  exit 2
}

base_sha=""
branch_prefix=""
while (($#)); do
  case "$1" in
    --base-sha)
      [[ $# -ge 2 ]] || usage
      base_sha="$2"
      shift 2
      ;;
    --branch-prefix)
      [[ $# -ge 2 ]] || usage
      branch_prefix="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

[[ "$base_sha" =~ ^[0-9a-f]{40}$ ]] || fail "base sha is not a full commit oid"
[[ "$branch_prefix" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || fail "branch prefix is unsafe"
[[ "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "GITHUB_REPOSITORY is unsafe"
command -v gh >/dev/null || fail "gh is unavailable"
command -v jq >/dev/null || fail "jq is unavailable"

current_sha="$(git rev-parse HEAD)" || fail "could not read the caller checkout head"
if [[ "$current_sha" == "$base_sha" ]]; then
  echo "No template-sync commit was created; signature replacement is unnecessary."
  exit 0
fi

branch="$(git branch --show-current)" || fail "could not read the generated branch"
[[ "$branch" == "${branch_prefix}_"* ]] ||
  fail "refusing to replace unexpected branch '$branch' (expected '${branch_prefix}_*')"

parent_line="$(git show -s --format=%P HEAD)" || fail "could not read the sync commit parent"
read -r -a parents <<<"$parent_line"
[[ ${#parents[@]} -eq 1 ]] || fail "sync commit must have exactly one parent"
[[ "${parents[0]}" == "$base_sha" ]] || fail "sync commit parent does not match the workflow base sha"

tree_sha="$(git show -s --format=%T HEAD)" || fail "could not read the sync commit tree"
message="$(git show -s --format=%B HEAD)" || fail "could not read the sync commit message"
[[ -n "$message" ]] || fail "sync commit message is empty"

ref_endpoint="repos/${GITHUB_REPOSITORY}/git/ref/heads/${branch}"
remote_ref="$(gh api "$ref_endpoint")" || fail "could not read the generated remote branch"
remote_sha="$(jq -er '.object.sha' <<<"$remote_ref")" || fail "generated remote branch response has no sha"
[[ "$remote_sha" == "$current_sha" ]] ||
  fail "generated remote branch moved after the sync action (expected $current_sha, found $remote_sha)"

# GitHub verifies bot signatures when an authenticated App creates a commit and
# the request omits custom author, committer, and signature fields:
# https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification#signature-verification-for-bots
commit_payload="$(
  jq -n \
    --arg message "$message" \
    --arg tree "$tree_sha" \
    --arg parent "${parents[0]}" \
    '{message:$message,tree:$tree,parents:[$parent]}'
)" || fail "could not build the replacement commit payload"

commit_response="$(
  gh api -X POST "repos/${GITHUB_REPOSITORY}/git/commits" --input - <<<"$commit_payload"
)" || fail "GitHub did not create the replacement commit"

signed_sha="$(jq -er '.sha' <<<"$commit_response")" || fail "replacement commit response has no sha"
verified="$(jq -r 'if (.verification | has("verified")) then .verification.verified else empty end' <<<"$commit_response")" ||
  fail "replacement commit response has no verification verdict"
[[ "$verified" == "true" || "$verified" == "false" ]] ||
  fail "replacement commit response has no verification verdict"
verification_reason="$(jq -r '.verification.reason // "unknown"' <<<"$commit_response")"
[[ "$verified" == "true" ]] ||
  fail "GitHub did not verify the App commit (reason=$verification_reason); branch remains unchanged"

update_payload="$(jq -n --arg sha "$signed_sha" '{sha:$sha,force:true}')" ||
  fail "could not build the branch update payload"
gh api -X PATCH "repos/${GITHUB_REPOSITORY}/git/refs/heads/${branch}" --input - \
  <<<"$update_payload" >/dev/null || fail "could not move the generated branch to the verified commit"

verified_commit="$(gh api "repos/${GITHUB_REPOSITORY}/commits/${signed_sha}")" ||
  fail "could not read back the replacement commit"
jq -e \
  --arg sha "$signed_sha" \
  --arg tree "$tree_sha" \
  --arg parent "${parents[0]}" \
  --arg message "$message" \
  '.sha == $sha
   and .commit.tree.sha == $tree
   and [.parents[].sha] == [$parent]
   and .commit.message == $message
   and .commit.verification.verified == true' \
  <<<"$verified_commit" >/dev/null || fail "replacement commit readback changed content or lost verification"

updated_ref="$(gh api "$ref_endpoint")" || fail "could not read back the generated branch"
updated_sha="$(jq -er '.object.sha' <<<"$updated_ref")" || fail "updated branch response has no sha"
[[ "$updated_sha" == "$signed_sha" ]] || fail "generated branch does not point to the verified replacement"

printf '%s\n' "$signed_sha"
