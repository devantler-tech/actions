#!/usr/bin/env bash
# Fail-closed review/pre-merge gate for the privileged auto-merge workflow.
#
# Usage: check-merge-gates.sh <head-sha> <head-seen-at> <reviews-json> <comments-json>
#   head-sha           the pull request's current head commit SHA
#   head-seen-at       ISO8601 time GitHub last saw the head BECOME the head
#                      (the caller passes the earliest check-suite created_at
#                      for the SHA — raised to the newest force-push time when
#                      the branch later returned to an earlier SHA). This is
#                      the freshness floor for the pre-merge summary, which
#                      CodeRabbit edits in place and which carries no commit
#                      SHA of its own. Commit metadata alone is NOT a safe
#                      floor: pushing a previously-created commit object
#                      carries an old committer date.
#   reviews-json       file holding the FULL paginated GraphQL review array,
#                      normalized to REST-style keys plus last_edited_at
#   comments-json      file holding the FULL paginated `issues/<n>/comments` array
#
# Exits 0 only when BOTH gates are proven at the current head:
#   1. a green review — CodeRabbit's LATEST review verdict at the head is
#      APPROVED (an earlier approval superseded by CHANGES_REQUESTED or a
#      dismissal is NOT green, and a COMMENTED review at the head that is not
#      explicitly clean supersedes an approval and blocks the Codex
#      fallback), or — when CodeRabbit has no blocking verdict at the head and
#      no current-head Codex findings review exists — the latest Codex result
#      comment is a clean pass ("Didn't find any major issues") whose
#      "Reviewed commit" equals the head;
#   2. a green CodeRabbit pre-merge result — the most recently UPDATED
#      auto-generated summary (stable marker required; CodeRabbit edits the
#      summary in place, so created_at alone selects a stale revision). That
#      newest summary itself must carry an unambiguously green pre-merge
#      section: a positive check-mark count and no error/inconclusive/warning
#      marks in either shape, and its update time must not be older than the
#      head-seen floor (a summary last touched before GitHub saw the head can
#      only describe an earlier state). A newer summary with no pre-merge
#      section — or a rate-limit overlay that retained an older green section —
#      supersedes the older result and fails closed.
#      When walkthrough boundary markers exist, only the bounded region is
#      parsed so echoed marker text elsewhere cannot spoof it.
#
# Everything else — missing, stale, mixed, unparseable, or absent state — is
# NOT green and exits 1 (the workflow declines approval and revokes stale
# arming; the maintenance agent acts after its own live pentad check). Never
# weaken this to warn-only.

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
  def effective_at:
    [.submitted_at, .last_edited_at] | map(select(. != null)) | max // "";
  [.[]
   | select(.user.login == "coderabbitai[bot]")
   | select(.commit_id == $sha)
   | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
            or .state == "DISMISSED")]
  | sort_by(effective_at) | last | .state // empty' "$reviews_json")"

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

# CodeRabbit posts incremental findings as a COMMENTED review WITHOUT issuing
# a verdict, so a COMMENTED review at the head that lands after the latest
# verdict (or with no verdict at all) must block a green outcome — it
# supersedes an earlier approval AND pre-empts the Codex fallback below. Only
# a body that explicitly proves clean ("Actionable comments posted: 0")
# preserves the state; a blank or unparseable body counts as findings
# (fail-closed — a bodyless COMMENTED review can still carry inline review
# comments). GraphQL lastEditedAt makes an edited older review supersede a
# later-submitted approval durably. The EXISTENCE marker line distinguishes
# "no such review" from "review with an empty body".
cr_commented_probe="$(jq -r --arg sha "$head_sha" '
  def effective_at:
    [.submitted_at, .last_edited_at] | map(select(. != null)) | max // "";
  ([.[]
    | select(.user.login == "coderabbitai[bot]")
    | select(.commit_id == $sha)
    | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED"
             or .state == "DISMISSED")]
   | sort_by(effective_at) | last | effective_at) as $verdict_at
  | [.[]
     | select(.user.login == "coderabbitai[bot]")
     | select(.commit_id == $sha)
     | select(.state == "COMMENTED")
     | select(effective_at >= $verdict_at)]
  | sort_by(effective_at) | last
  | if . == null then "absent" else "present\n" + (.body // "") end' "$reviews_json")"

if [[ "$cr_commented_probe" == present* &&
  "$cr_commented_probe" != *"Actionable comments posted: 0"* ]]; then
  review_state="needs-fix"
fi

# Codex lane: clean results are ISSUE COMMENTS carrying "**Reviewed commit:**
# <sha>" (often abbreviated), while findings arrive as review objects at the
# exact head. Any current-head findings review is red evidence even when a
# later clean comment exists. This conservative result can only withhold the
# workflow's approval; the maintenance agent still evaluates the live pentad.
# An abbreviated clean SHA is accepted only when GitHub's commit endpoint
# resolves it uniquely to the exact head; raw prefix matching is not proof.
codex_findings_at_head="$(jq -r --arg sha "$head_sha" '
  [.[]
   | select(.user.login == "chatgpt-codex-connector[bot]")
   | select((.commit_id // "" | ascii_downcase) == ($sha | ascii_downcase))
   | select(.state == "COMMENTED" or .state == "CHANGES_REQUESTED")]
  | length' "$reviews_json")"

latest_codex_comment_probe="$(jq -r '
  [.[]
     | select(.user.login == "chatgpt-codex-connector[bot]")
     | (.body // "") as $body
     | select($body | contains("Codex Review:"))
     | ([try ($body
          | capture("\\*\\*Reviewed commit:\\*\\*[[:space:]]*`?(?<sha>[0-9a-fA-F]{7,40})")
          | .sha) catch ""]
        | first // "" | ascii_downcase) as $reviewed
     | {at: (.updated_at // .created_at), reviewed: $reviewed, body: $body}]
  | sort_by(.at) | last
  | if . == null then "absent"
    else "present\n" + .reviewed + "\n" + .body
    end' "$comments_json")"

if [[ "$codex_findings_at_head" -gt 0 ]]; then
  review_state="needs-fix"
elif [[ "$latest_codex_comment_probe" == present* ]]; then
  latest_codex_payload="${latest_codex_comment_probe#*$'\n'}"
  latest_codex_reviewed="${latest_codex_payload%%$'\n'*}"
  latest_codex_body="${latest_codex_payload#*$'\n'}"
  codex_comment_matches_head=false

  if [[ ${#latest_codex_reviewed} -eq 40 && "$latest_codex_reviewed" == "$head_sha" ]]; then
    codex_comment_matches_head=true
  elif [[ ${#latest_codex_reviewed} -lt 40 && -n "${REPOSITORY:-}" ]]; then
    resolved_codex_sha=""
    if resolved_codex_sha=$(gh api \
      "repos/$REPOSITORY/commits/$latest_codex_reviewed" --jq .sha 2>/dev/null) &&
      [[ "$resolved_codex_sha" == "$head_sha" ]]; then
      codex_comment_matches_head=true
    fi
  fi

  if [[ "$codex_comment_matches_head" == "true" &&
    "$latest_codex_body" == *"Didn't find any major issues"* ]]; then
    if [[ "$review_state" == "missing" || "$review_state" == "stale" ]]; then
      review_state="green"
    fi
  elif [[ "$codex_comment_matches_head" == "true" ]]; then
    review_state="needs-fix"
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
   | select(.body | contains($marker))]
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
  elif [[ "$premerge_body" == *'<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->'* ||
    "$premerge_body" == *"## Review limit reached"* ]]; then
    # CodeRabbit edits the existing summary when rate-limited and can retain
    # the previous run's compact `✅ 5` section underneath the warning. That
    # stale display is not a current evaluation and must never become green.
    premerge_state="inconclusive"
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
      # Full shape: every Markdown check row must explicitly be `✅ Passed`.
      # Header/separator rows are ignored; an unknown/pending data row is red
      # even when another row passed. Requiring at least one data row keeps an
      # unrecognized future shape fail-closed.
      full_check_rows="$(awk '
        /^## Pre-merge checks[[:space:]]*$/ { in_section = 1; next }
        in_section && /^##[[:space:]]/ { exit }
        in_section && /^\|/ {
          if ($0 ~ /^\|[-[:space:]:|]+\|[[:space:]]*$/) next
          if ($0 ~ /\|[[:space:]]*(Status|Result)[[:space:]]*\|/) next
          print
        }
      ' <<<"$region")"
      if [[ -n "$full_check_rows" && "$region" != *"❌"* &&
        "$region" != *"❓"* && "$region" != *"⚠️"* ]] &&
        ! grep -qvF '✅ Passed' <<<"$full_check_rows"; then
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
