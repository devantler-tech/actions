#!/usr/bin/env bash
# Offline API boundary. Never fall back to the installed gh executable.
set -euo pipefail
[[ "${1:-}" == api ]] || exit 90
endpoint="${2:-}"
shift 2
printf '%s\n' "$endpoint" >> "$CASE_ROOT/api.log"
case "$endpoint" in
  graphql)
    [[ "${1:-}" == --input && $# == 2 ]] || exit 91
    cp "$2" "$CASE_ROOT/request.json"
    jq -e --arg repo "$REPO" --arg branch "$BRANCH" --arg head "$BASE_SHA" --arg message "$COMMIT_MESSAGE" '
      .variables.input as $i |
      $i.branch.repositoryNameWithOwner == $repo and
      $i.branch.branchName == $branch and $i.expectedHeadOid == $head and
      $i.message.headline == $message and
      ($i | has("author") or has("committer") or has("signature") | not)
    ' "$CASE_ROOT/request.json" >/dev/null || exit 92
    case "$API_MODE" in
      stale) printf '{"errors":[{"message":"expected head mismatch"}]}\n'; exit 1 ;;
      rejected) printf '{"errors":[{"message":"fixture rejected mutation"}]}\n'; exit 1 ;;
      errors) printf '{"errors":[{"message":"fixture GraphQL error"}]}\n'; exit 0 ;;
    esac
    # The API publishes before the verification read. Even a lost/malformed
    # response cannot establish that no write occurred.
    printf '%s\n' "$CREATED_SHA" > "$CASE_ROOT/remote-head"
    case "$API_MODE" in
      empty) exit 0 ;;
      malformed) printf 'not JSON\n'; exit 0 ;;
      missing-oid) printf '{"data":{"createCommitOnBranch":{"commit":{}}}}\n'; exit 0 ;;
    esac
    jq -n --arg oid "$CREATED_SHA" '{data:{createCommitOnBranch:{commit:{oid:$oid}}}}'
    ;;
  "repos/$REPO/commits/$HEAD_SHA"|"repos/$REPO/commits/$CREATED_SHA")
    if [[ $# == 0 ]]; then
      [[ "$endpoint" == "repos/$REPO/commits/$HEAD_SHA" ]] || exit 93
      [[ "$READ_FAILURE" != head ]] || exit 1
      cat "$CASE_ROOT/head.json"
    else
      [[ $# == 2 && "$1" == --jq ]] || exit 94
      [[ "$READ_FAILURE" != verification ]] || exit 1
      jq -r "$2" "$CASE_ROOT/verification.json"
    fi
    ;;
  *) printf 'Unexpected fixture API endpoint\n' >&2; exit 95 ;;
esac
