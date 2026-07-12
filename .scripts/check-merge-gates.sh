#!/usr/bin/env bash
# Fail-closed review/pre-merge gate for the privileged auto-merge workflow.
#
# Usage: check-merge-gates.sh <head-sha> <head-seen-at> <reviews-json> <comments-json>
#   head-sha           the pull request's current head commit SHA
#   head-seen-at       ISO8601 time GitHub last saw the head BECOME the head
#                      (the caller passes the earliest check-suite created_at
#                      for the SHA — raised to the newest force-push time when
#                      the branch later returned to an earlier SHA — falling
#                      back to the committer date) — the freshness floor for the
#                      pre-merge summary, which CodeRabbit edits in place and
#                      which carries no commit SHA of its own. Commit metadata
#                      alone is NOT a safe floor: pushing a previously-created
#                      commit object carries an old committer date.
#   reviews-json       file holding the FULL paginated `pulls/<n>/reviews` array
#   comments-json      file holding the FULL paginated `issues/<n>/comments` array
#
# Exits 0 only when BOTH gates are proven at the current head:
#   1. a green review — CodeRabbit's LATEST review verdict at the head is
#      APPROVED (an earlier approval superseded by CHANGES_REQUESTED or a
#      dismissal is NOT green, and a later COMMENTED review at the head
#      carrying actionable findings supersedes the approval too), or — when
#      CodeRabbit has no verdict at the head — a Codex clean pass ("Didn't
#      find any major issues") whose "Reviewed commit" equals the head and is
#      Codex's LATEST result for it;
#   2. a green CodeRabbit pre-merge result — the most recently UPDATED
#      auto-generated summary (stable marker required; CodeRabbit edits the
#      summary in place, so created_at alone selects a stale revision) whose
#      pre-merge section is unambiguously green: a positive check-mark count
#      and no error/inconclusive/warning marks in either shape, and whose
#      update time is not older than the head-seen floor (a summary last
#      touched before GitHub saw the head can only describe an earlier state).
#      When walkthrough boundary markers exist, only the bounded region is
#      parsed so echoed marker text elsewhere cannot spoof it.
#
# Everything else — missing, stale, mixed, unparseable, or absent state — is
# NOT green and exits 1 (the workflow then skips arming; the maintenance
# agent arms after its own live pentad check). Never weaken this to warn-only.

set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: $0 <head-sha> <head-seen-at> <reviews-json> <comments-json>" >&2
  exit 2
fi

head_sha="$1"
head_seen_at="$2"
reviews_json="$3"
comments_json="$4"

review_state="missing"
premerge_state="not-posted"

# --- Gate 1: green review at the current head -------------------------------

# CodeRabbit's verdict at the head is its LATEST verdict-bearing review there:
# an APPROVED superseded by CHANGES_REQUESTED (or dismissed) must not count.
cr_latest_verdict_at_head="$(jq -r --arg sha "$head_sha" '
  [.[]
   | select(.user.login == "coderabbitai[bot]")
   | select(.commit_id == $sha)
   | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
            or .state == "DISMISSED")]
  | sort_by(.submitted_at) | last | .state // empty' "$reviews_json")"

cr_approved_anywhere="$(jq -r '
  [.[] | select(.user.login == "coderabbitai[bot]" and .state == "APPROVED")]
  | length' "$reviews_json")"

if [[ "$cr_latest_verdict_at_head" == "APPROVED" ]]; then
  review_state="green"
elif [[ -n "$cr_latest_verdict_at_head" ]]; then
  # An explicit non-approval verdict at the head blocks arming outright — a
  # Codex clean pass must not override CodeRabbit's CHANGES_REQUESTED.
  review_state="needs-fix"
elif [[ "$cr_approved_anywhere" -gt 0 ]]; then
  review_state="stale"
fi

# CodeRabbit posts incremental findings as a COMMENTED review WITHOUT revoking
# its earlier approval, so a COMMENTED review at the head that lands after the
# approval and carries actionable findings must supersede it. A clean
# incremental pass ("Actionable comments posted: 0") keeps the approval; a
# body that cannot be proven clean is treated as findings (fail-closed).
if [[ "$review_state" == "green" ]]; then
  cr_commented_after_verdict="$(jq -r --arg sha "$head_sha" '
    ([.[]
      | select(.user.login == "coderabbitai[bot]")
      | select(.commit_id == $sha)
      | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
               or .state == "DISMISSED")]
     | sort_by(.submitted_at) | last | .submitted_at // "") as $verdict_at
    | [.[]
       | select(.user.login == "coderabbitai[bot]")
       | select(.commit_id == $sha)
       | select(.state == "COMMENTED")
       | select(.submitted_at > $verdict_at)]
    | sort_by(.submitted_at) | last | .body // empty' "$reviews_json")"

  if [[ -n "$cr_commented_after_verdict" &&
    "$cr_commented_after_verdict" != *"Actionable comments posted: 0"* ]]; then
    review_state="needs-fix"
  fi
fi

if [[ "$review_state" == "missing" || "$review_state" == "stale" ]]; then
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

# CodeRabbit EDITS its auto-generated summary in place across review cycles,
# so the newest revision is the one with the greatest updated_at (falling back
# to created_at), never the newest created_at alone. One call returns the
# selected summary's touch time on the first line and its body after it.
premerge_selected="$(jq -r --arg marker "$summary_marker" '
  [.[]
   | select(.user.login == "coderabbitai[bot]")
   | select(.body | contains($marker))
   | select((.body | contains("## Pre-merge checks"))
            or (.body | contains("<summary>🚥 Pre-merge checks |")))]
  | sort_by(.updated_at // .created_at) | last
  | if . == null then empty
    else ((.updated_at // .created_at) // "") + "\n" + .body end' "$comments_json")"

premerge_touched_at="${premerge_selected%%$'\n'*}"
premerge_body="${premerge_selected#*$'\n'}"

if [[ -n "$premerge_body" ]]; then
  # The summary carries no commit SHA, so freshness is the proxy tie to the
  # head: a summary last updated before GitHub first saw the head can only
  # describe an earlier state. ISO8601 Zulu timestamps compare lexically.
  if [[ -n "$head_seen_at" && "$premerge_touched_at" < "$head_seen_at" ]]; then
    premerge_state="stale"
  else
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
      # bounded region carries no error/inconclusive/warning mark at all.
      if [[ "$region" == *"✅"* && "$region" != *"❌"* &&
        "$region" != *"❓"* && "$region" != *"⚠️"* ]]; then
        premerge_state="green"
      else
        premerge_state="failed"
      fi
    else
      premerge_state="inconclusive"
    fi
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
