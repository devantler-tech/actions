#!/usr/bin/env bash
# Fail-closed review/pre-merge gate for the privileged auto-merge workflow.
#
# Usage: check-merge-gates.sh <head-sha> <reviews-json> <comments-json>
#   head-sha      the pull request's current head commit SHA
#   reviews-json  file holding the FULL paginated `pulls/<n>/reviews` array
#   comments-json file holding the FULL paginated `issues/<n>/comments` array
#
# Exits 0 only when BOTH gates are proven at the current head:
#   1. a green review — a CodeRabbit APPROVED review whose commit_id equals
#      the head, or a Codex clean pass ("Didn't find any major issues") whose
#      "Reviewed commit" equals the head and is Codex's LATEST result for it;
#   2. a green CodeRabbit pre-merge result — the newest auto-generated summary
#      (stable marker required) whose pre-merge section is unambiguously
#      green: a positive check-mark count and no error/inconclusive/warning
#      marks. When walkthrough boundary markers exist, only the bounded
#      region is parsed so echoed marker text elsewhere cannot spoof it.
#
# Everything else — missing, stale, mixed, unparseable, or absent state — is
# NOT green and exits 1 (the workflow then skips arming; the maintenance
# agent arms after its own live pentad check). Never weaken this to warn-only.

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <head-sha> <reviews-json> <comments-json>" >&2
  exit 2
fi

head_sha="$1"
reviews_json="$2"
comments_json="$3"

review_state="missing"
premerge_state="not-posted"

# --- Gate 1: green review at the current head -------------------------------

cr_approved_at_head="$(jq -r --arg sha "$head_sha" '
  [.[] | select(.user.login == "coderabbitai[bot]" and .state == "APPROVED")]
  | map(select(.commit_id == $sha)) | length' "$reviews_json")"

cr_approved_anywhere="$(jq -r '
  [.[] | select(.user.login == "coderabbitai[bot]" and .state == "APPROVED")]
  | length' "$reviews_json")"

if [[ "$cr_approved_at_head" -gt 0 ]]; then
  review_state="green"
elif [[ "$cr_approved_anywhere" -gt 0 ]]; then
  review_state="stale"
fi

if [[ "$review_state" != "green" ]]; then
  # Codex lane: its result is an ISSUE COMMENT carrying "**Reviewed commit:**
  # <sha>". Only the LATEST Codex result for the current head counts — an
  # older clean pass superseded by a findings run must not read as green.
  latest_codex_at_head="$(jq -r --arg sha "$head_sha" '
    [.[]
     | select(.user.login == "chatgpt-codex-connector[bot]")
     | select(.body | contains($sha))]
    | sort_by(.created_at) | last | .body // empty' "$comments_json")"

  if [[ -n "$latest_codex_at_head" ]]; then
    if [[ "$latest_codex_at_head" == *"Didn't find any major issues"* ]]; then
      review_state="green"
    else
      review_state="needs-fix"
    fi
  fi
fi

# --- Gate 2: green CodeRabbit pre-merge result ------------------------------

summary_marker='<!-- This is an auto-generated comment: summarize by coderabbit.ai -->'

premerge_body="$(jq -r --arg marker "$summary_marker" '
  [.[]
   | select(.user.login == "coderabbitai[bot]")
   | select(.body | contains($marker))
   | select((.body | contains("## Pre-merge checks"))
            or (.body | contains("<summary>🚥 Pre-merge checks |")))]
  | sort_by(.created_at) | last | .body // empty' "$comments_json")"

if [[ -n "$premerge_body" ]]; then
  region="$premerge_body"
  if [[ "$premerge_body" == *'<!-- pre_merge_checks_walkthrough_start -->'* &&
    "$premerge_body" == *'<!-- pre_merge_checks_walkthrough_end -->'* ]]; then
    region="${premerge_body#*<!-- pre_merge_checks_walkthrough_start -->}"
    region="${region%%<!-- pre_merge_checks_walkthrough_end -->*}"
  fi

  compact_line="$(grep -oE '🚥 Pre-merge checks \|[^<]*' <<<"$region" | head -n 1 || true)"
  if [[ -n "$compact_line" ]]; then
    # Compact shape: green only with a positive ✅ count and no positive
    # ❌ / ❓ / ⚠️ counter anywhere in the summary line.
    if grep -qE '✅ [1-9][0-9]*' <<<"$compact_line" &&
      ! grep -qE '(❌|❓|⚠️) *[1-9][0-9]*' <<<"$compact_line"; then
      premerge_state="green"
    else
      premerge_state="failed"
    fi
  elif [[ "$region" == *"## Pre-merge checks"* ]]; then
    # Full shape: green only when at least one explicit pass exists and the
    # bounded region carries no error/inconclusive mark at all.
    if [[ "$region" == *"✅"* && "$region" != *"❌"* && "$region" != *"❓"* ]]; then
      premerge_state="green"
    else
      premerge_state="failed"
    fi
  else
    premerge_state="inconclusive"
  fi
fi

# --- Verdict -----------------------------------------------------------------

echo "review=$review_state"
echo "premerge=$premerge_state"

if [[ "$review_state" == "green" && "$premerge_state" == "green" ]]; then
  echo "gates=green"
  exit 0
fi

echo "gates=not-green (fail-closed: arming skipped)"
exit 1
