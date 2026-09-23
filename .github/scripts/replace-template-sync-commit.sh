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

# Shared-workflow pins never move backwards (#1239). Template sync copies the TEMPLATE's
# devantler-tech/actions pins over the target's, so a template that lags its consumer would
# downgrade it: devantler-tech/wedding-app#332 replaced three v13.6.0 pins with v13.5.1 while every
# check stayed green, because both pins were approved. Each changed pin is therefore ordered against
# the target's pin for the same path with GitHub's compare API (commit ancestry, never the mutable
# `# vX.Y.Z` comment). Where the template's pin is behind or diverged, the target's whole line is
# kept; only that corrected tree is signed. An ordering the API cannot answer, or a regressive line
# the template also reshaped, fails closed before anything is signed.
actions_repo="devantler-tech/actions"
pin_pattern="${actions_repo}(/[^@[:space:]]*)?@[0-9a-f]{40}"
work="$(mktemp -d)" || fail "could not create a work directory"
trap 'rm -rf "$work"' EXIT

pins_at() {
  # pins_at <rev> <path>: every distinct pin in that revision of the file, one per line.
  local content
  git cat-file -e "$1:$2" 2>/dev/null || return 0
  content="$(git show "$1:$2")" || fail "could not read $2 at $1"
  { grep -oE "$pin_pattern" <<<"$content" || true; } | sort -u
}

corrected=()
restore_pin() {
  # restore_pin <path> <template-ref> <target-ref>: in the corrected copy of <path>, put the
  # target's line back wherever the template's pin sits, provided nothing else on it changed.
  local path="$1" new_ref="$2" old_ref="$3" copy base_content old_line
  copy="$work/files/$path"
  if [[ ! -f "$copy" ]]; then
    mkdir -p "$(dirname "$copy")"
    git show "HEAD:$path" >"$copy" || fail "could not read $path"
    corrected+=("$path")
  fi
  base_content="$(git show "$base_sha:$path")" || fail "could not read $path at the target head"
  old_line="$(grep -F -m1 -- "$old_ref" <<<"$base_content")" ||
    fail "could not find the target's $old_ref line in $path"
  NEW_REF="$new_ref" OLD_REF="$old_ref" OLD_LINE="$old_line" awk '
    BEGIN { old_prefix = substr(ENVIRON["OLD_LINE"], 1, index(ENVIRON["OLD_LINE"], ENVIRON["OLD_REF"]) - 1) }
    {
      i = index($0, ENVIRON["NEW_REF"])
      if (i == 0) { print; next }
      if (substr($0, 1, i - 1) != old_prefix) { reshaped = 1; print; next }
      print ENVIRON["OLD_LINE"]
    }
    END { exit reshaped ? 3 : 0 }
  ' "$copy" >"$copy.next" ||
    fail "cannot restore the target's $old_ref in $path: the template also changed the rest of that line; refusing to sign a downgrade"
  mv "$copy.next" "$copy"
}

git diff -z --name-only --no-renames "$base_sha" HEAD >"$work/changed" ||
  fail "could not list the files the sync commit changed"
while IFS= read -r -d '' path; do
  new_pins="$(pins_at HEAD "$path")"
  [[ -n "$new_pins" ]] || continue
  old_pins="$(pins_at "$base_sha" "$path")"
  [[ -n "$old_pins" ]] || continue
  while IFS= read -r new_ref; do
    grep -qxF -- "$new_ref" <<<"$old_pins" && continue
    new_pin="${new_ref##*@}"
    while IFS= read -r old_ref; do
      [[ "${old_ref%@*}" == "${new_ref%@*}" ]] || continue
      old_pin="${old_ref##*@}"
      if ! comparison="$(gh api "repos/${actions_repo}/compare/${old_pin}...${new_pin}" </dev/null)" ||
        ! status="$(jq -er '.status' <<<"$comparison")"; then
        fail "could not order ${new_ref} against the target's ${old_pin}; refusing to sign an unverified pin change"
      fi
      case "$status" in
        ahead | identical) continue ;;
        behind | diverged) ;;
        *) fail "unexpected compare status '$status' for ${new_ref}; refusing to sign" ;;
      esac
      restore_pin "$path" "$new_ref" "$old_ref"
      echo "::warning file=${path}::Template sync kept ${old_ref}: the template's ${new_pin} is ${status} it, so that downgrade was left out."
      break
    done <<<"$old_pins"
  done <<<"$new_pins"
done <"$work/changed"

if ((${#corrected[@]} > 0)); then
  # Build the corrected tree locally, then have GitHub build it from the posted content, and sign
  # only if both agree byte for byte.
  index="$work/index"
  GIT_INDEX_FILE="$index" git read-tree HEAD || fail "could not stage the sync tree"
  entries='[]'
  for path in "${corrected[@]}"; do
    mode="$(git ls-tree HEAD -- "$path" | cut -d' ' -f1)"
    [[ "$mode" == "100644" || "$mode" == "100755" ]] || fail "unexpected file mode '$mode' for $path"
    blob="$(git hash-object -w -- "$work/files/$path")" || fail "could not hash the corrected $path"
    GIT_INDEX_FILE="$index" git update-index --cacheinfo "$mode,$blob,$path" ||
      fail "could not stage the corrected $path"
    entries="$(jq --arg path "$path" --arg mode "$mode" --rawfile content "$work/files/$path" \
      '. + [{path:$path,mode:$mode,type:"blob",content:$content}]' <<<"$entries")" ||
      fail "could not encode the corrected $path"
  done
  local_tree="$(GIT_INDEX_FILE="$index" git write-tree)" || fail "could not write the corrected tree"
  tree_payload="$(jq -n --arg base "$tree_sha" --argjson tree "$entries" '{base_tree:$base,tree:$tree}')" ||
    fail "could not build the corrected tree payload"
  tree_response="$(gh api -X POST "repos/${GITHUB_REPOSITORY}/git/trees" --input - <<<"$tree_payload")" ||
    fail "GitHub did not create the corrected tree"
  remote_tree="$(jq -er '.sha' <<<"$tree_response")" || fail "corrected tree response has no sha"
  [[ "$remote_tree" == "$local_tree" ]] ||
    fail "GitHub built the corrected tree as $remote_tree, not the expected $local_tree; refusing to sign"
  tree_sha="$local_tree"
fi

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
