#!/usr/bin/env bash
# Guards the `test` job's TRIGGER conditions in validate-go-project.yaml
# (devantler-tech/ksail#6373).
#
# `needs.changes.outputs.go` answers "did a Go SOURCE file change". The Go test suite's
# verdict does not depend only on that: a Go test may read a NON-Go file as its subject,
# so a commit that touches only such files leaves `go == 'false'` — correctly, the filter
# is not misconfigured — and skips the suite while breaking it.
#
# Measured on ksail: `internal/ciharness` asserts against `.github/workflows/*.yaml` and
# `.github/scripts/*.sh`. Commit `a5ed9f85` (#6363) moved an EKS teardown guard out of a
# workflow's inline `run:` into a script and broke
# `TestEKSSmokePreparesCloudGitOpsAndBoundsCleanup`. That push to `main` changed four
# files, NONE of them Go, so 🧪 Test was skipped and `main` reported green — and every
# later `main` run repeated that verdict, until an unrelated pull request that happened to
# touch Go files inherited the failure and paid for the diagnosis.
#
# On the default branch the diff is not a sound basis for this decision at all: that
# branch's green IS the branch-protection signal, so it has to mean the suite ran. Fixing
# it changes behaviour in every consumer at once, so the default-branch run ships behind
# the opt-in input `test-default-branch` (AGENTS.md, *Shipping a new capability behind an
# opt-in flag*), making the gate a two-armed expression whose BOTH arms this guard asserts:
#
#   * the flagged arm must actually be REACHABLE — the default-branch clause OR-ed with the
#     diff gate, not AND-ed alongside it, and no top-level predicate able to veto it;
#   * the unflagged arm must not have GROWN — nothing may become reachable without opting
#     in, which is what keeps the change backward compatible for a caller passing nothing.
#
# Everything is asserted POSITIVELY — the intended property must hold — rather than by
# rejecting one known-bad string. A test that merely rejects a specific bad predicate still
# passes when the job is restricted some other way, and would then claim default-branch
# coverage over a workflow that never runs the suite there.
#
# This deliberately mirrors test-govulncheck-main-coverage.sh, which guards the same
# property for the vulnerability scan. The three expression-parsing helpers are duplicated
# rather than shared: extracting them is a pure refactor and belongs in its own change, not
# folded into a behaviour change (devantler-tech/actions#869).

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"

flag_input="test-default-branch"
flag_ref="inputs.${flag_input}"

status=0

fail() {
  echo "::error file=$workflow::$1"
  status=1
}

# Collapse the gate to one whitespace-normalised line so the structural checks below do not
# depend on how the YAML block scalar happens to be wrapped.
gate="$(yq -r '.jobs.test.if // ""' "$workflow")"
flat="$(tr '\n' ' ' <<<"$gate" | tr -s ' ')"

# Rewrite function-call parentheses — `format('refs/heads/{0}', x)` — into angle brackets,
# preserving their contents. Without this the call's parens are indistinguishable from
# grouping parens, which both hides the real group and makes `default_branch` (an argument
# to such a call) impossible to attribute to the group it actually guards.
defun() {
  local s="$1" prev=""
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="$(sed -E 's/([A-Za-z_][A-Za-z0-9_.-]*)\(([^()]*)\)/\1<\2>/g' <<<"$s")"
  done
  printf '%s' "$s"
}

# Repeatedly delete innermost parenthesised groups, leaving only the top-level conjuncts. A
# term that survives this is AND-ed at the top level and can therefore veto the job on its
# own, whatever else the gate says.
strip_groups() {
  local s="$1" prev=""
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="$(sed -E 's/\([^()]*\)/ /g' <<<"$s")"
  done
  printf '%s' "$s"
}

# Split a parenthesised group into its top-level `||` arms, one per line. Balance-scanned
# rather than split on `||`, because an arm may itself contain a parenthesised `||`.
split_arms() {
  awk '
    {
      s = $0
      # Strip one enclosing layer of parens, but only when the leading "(" is the partner
      # of the trailing ")" — in "(a) || (b)" it is not, and stripping would corrupt.
      if (substr(s, 1, 1) == "(") {
        d = 0
        for (i = 1; i <= length(s); i++) {
          c = substr(s, i, 1)
          if (c == "(") d++
          else if (c == ")") { d--; if (d == 0) break }
        }
        if (i == length(s)) s = substr(s, 2, length(s) - 2)
      }
      depth = 0; arm = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") depth++
        else if (c == ")") depth--
        if (depth == 0 && c == "|" && substr(s, i + 1, 1) == "|") {
          print arm; arm = ""; i++; continue
        }
        arm = arm c
      }
      print arm
    }' <<<"$1"
}

# Extract the OUTERMOST parenthesised group containing the path-filter term, by
# balance-scanning rather than by regex. A regex bounded with `[^()]*` can only match a
# group with no nesting, so it silently returns the INNERMOST group — and the flagged arm
# of this gate legitimately nests.
outer_group_with() {
  awk -v needle="$2" '
    { s = $0; depth = 0; start = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "(") { if (depth == 0) start = i; depth++ }
        else if (c == ")") {
          depth--
          if (depth == 0 && start > 0) {
            g = substr(s, start, i - start + 1)
            if (index(g, needle) > 0) { print g; exit }
          }
        }
      }
    }' <<<"$1"
}

# Everything in the expression EXCEPT the arm-group, with the group excised exactly once.
# This is what makes "term X may not veto the whole job" checkable without relying on
# `strip_groups`, which deletes parenthesised text wholesale and would therefore report a
# PARENTHESISED top-level conjunct — `&& (inputs.f == true || inputs.f == 'true') &&` — as
# absent. That shape ANDs the flag at the top level while satisfying a strip_groups-based
# check, so a caller that never opted in would silently lose the job entirely.
outside_group() {
  local whole="$1" grp="$2"
  local prefix="${whole%%"$grp"*}"
  local suffix="${whole#*"$grp"}"
  printf '%s %s' "$prefix" "$suffix"
}

if [[ -z "$gate" || "$gate" == "null" ]]; then
  fail "the test job has no 'if:' gate to verify"
else
  normalized="$(defun "$flat")"
  top_level="$(strip_groups "$normalized")"
  arm_group="$(outer_group_with "$normalized" "needs.changes.outputs.go" || true)"
  if [[ -n "$arm_group" ]]; then
    outside="$(outside_group "$normalized" "$arm_group")"
  else
    outside="$normalized"
  fi

  # ── 1. No single event may gate the whole job ─────────────────────────────────────
  # Scoped to the TOP LEVEL. An event equality inside an OR-arm is legitimate; a top-level
  # one vetoes every arm, so no opt-in could ever reach the default-branch run.
  if grep -qE "github\.event_name[[:space:]]*==" <<<"$top_level"; then
    fail "the test job AND-s 'github.event_name ==' at the top level, so whole classes of run — including the default branch — can never run the suite, whatever the opt-in input says. An event equality belongs inside an OR-arm, not alongside it; see ksail#6373."
  fi

  # ── 2. A default-branch run must be able to test regardless of the diff ───────────
  if ! grep -qF 'default_branch' <<<"$flat"; then
    fail "the test job's gate has no default-branch clause, so the path filter is the only gate on the default branch and a commit that breaks the suite without touching a Go file leaves it unrun while reporting green. Add: || github.ref == format('refs/heads/{0}', github.event.repository.default_branch) — see ksail#6373."
  fi

  # ── 3. The opt-in input must gate the new capability, not the whole job ───────────
  if ! grep -qF "$flag_ref" <<<"$flat"; then
    fail "the test job's gate does not reference '$flag_ref', so the default-branch run is not behind the opt-in input it is required to ship behind — a behaviour change landing on every consumer at once. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
  elif grep -qF "$flag_ref" <<<"$outside"; then
    fail "the test job references '$flag_ref' OUTSIDE the OR-group that holds the path filter, so it is AND-ed at the top level and a caller that does not opt in loses the diff-triggered suite it has today. The input must gate the default-branch arm only — see AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
  fi

  # ── 4. The path filter must not be able to veto a default-branch run ──────────────
  # The diff gate has to sit inside an OR-group with the default-branch clause. If it is a
  # top-level conjunct instead, the default-branch clause is decorative: `go == 'true'`
  # still has to hold, which is exactly the state check 2 exists to prevent.
  if grep -qF "needs.changes.outputs.go == 'true'" <<<"$outside"; then
    fail "the test job AND-s the path filter (needs.changes.outputs.go == 'true') at the top level, so a default-branch run with no Go paths changed is still skipped. The path filter must be OR-ed with the default-branch clause, not AND-ed alongside it — see ksail#6373."
  elif grep -qE 'github\.(ref|ref_name|head_ref|base_ref)' <<<"$top_level"; then
    # The legitimate default-branch clause lives inside the OR-group and has already been
    # stripped by now, so any ref predicate still standing here is an ADDITIONAL top-level
    # conjunct. `&& github.ref != 'refs/heads/main'` would satisfy the checks above while
    # making default-branch runs unreachable — the state this file exists to prevent.
    fail "the test job AND-s a top-level ref predicate, which can exclude the default branch no matter what the OR-ed default-branch clause says. A ref condition belongs inside that OR-group, not alongside it — see ksail#6373."
  else
    group="$arm_group"
    if [[ -z "$group" ]]; then
      fail "could not find the parenthesised group holding the path-filter term; the gate's structure is not what this guard can verify — see ksail#6373."
    elif ! grep -qF 'default_branch' <<<"$group"; then
      fail "the path-filter term is grouped, but not with the default-branch clause, so a default-branch run with no Go paths changed is still skipped — see ksail#6373."
    elif ! grep -qF '||' <<<"$group"; then
      fail "the path-filter term and the default-branch clause share a group but are not OR-ed, so the default-branch clause cannot rescue a run the path filter rejected — see ksail#6373."
    else
      # ── 4b. The base diff-trigger must SURVIVE as a real OR-alternative ───────────
      # Check 4's `||` presence test is not sufficient on its own, and cannot be made
      # sufficient: the flag-normalisation idiom this file requires elsewhere
      # (`inputs.X == true || inputs.X == 'true'`) contributes a literal `||` nested one
      # level inside the group, so the group contains a `||` even when its top level is a
      # pure conjunction.
      #
      # The gate that exploits that — reproduced against this guard before the check was
      # added, and it PASSED:
      #
      #   A && ( (inputs.test-default-branch == true || …== 'true') && go != '' && <db> )
      #
      # There the base trigger is gone entirely, so the job runs ONLY for callers that opt
      # in and every other consumer silently loses its diff-triggered test run — the exact
      # backward-compatibility property checks 3 and 6 exist to protect. It slips through
      # because `outside` holds no path-filter term to catch (check 4), the group really
      # does contain `default_branch` and a `||`, and `split_arms` returns a single arm
      # that legitimately carries the flag, the ran-proof and the default-branch clause,
      # satisfying checks 5, 6 and 7.
      #
      # Asserting the arm EXACTLY, rather than merely that one contains the term, is
      # deliberate: an arm of `go == 'true' && github.event_name == 'pull_request'` would
      # also be a regression for push consumers, and a containment test would accept it.
      base_arm_found=0
      while IFS= read -r arm; do
        trimmed="$(sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' <<<"$arm")"
        [[ "$trimmed" == "needs.changes.outputs.go == 'true'" ]] && base_arm_found=1
      done < <(split_arms "$group")
      if [[ "$base_arm_found" -eq 0 ]]; then
        fail "no top-level OR-arm of the group is exactly \"needs.changes.outputs.go == 'true'\", so the base diff-trigger is not OR-ed with the flagged arm — the group's '||' may be nothing but the flag's own true/'true' normalisation. A caller that does not opt in would lose the diff-triggered test run it has today. See ksail#6373."
      fi

      # ── 5. The default-branch clause must sit in the arm the input gates ──────────
      # Otherwise the input is referenced (check 3) but guards something else, and the new
      # behaviour is reachable without opting in.
      flagged_arm_has_default_branch=0
      while IFS= read -r arm; do
        if grep -qF "$flag_ref" <<<"$arm" && grep -qF 'default_branch' <<<"$arm"; then
          flagged_arm_has_default_branch=1
        fi
      done < <(split_arms "$group")
      if [[ "$flagged_arm_has_default_branch" -eq 0 ]]; then
        fail "no OR-arm both references '$flag_ref' and carries the default-branch clause, so the default-branch run is not the thing the opt-in input actually gates. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
      fi

      # ── 6. Nothing new may become reachable without opting in ─────────────────────
      # The backward-compatibility property, asserted directly. This job legitimately runs
      # on pushes today (whenever the diff touched Go), so — unlike the vuln scan's guard —
      # the unflagged arms cannot be required to be pull-request-only. What they must not
      # do is widen: an arm the input does not gate may not introduce a ref or
      # default-branch predicate of its own. Without this an arm could be added that fires
      # on every consumer's default branch, and checks 1-5 would all still pass.
      while IFS= read -r arm; do
        [[ -n "${arm// /}" ]] || continue
        grep -qF "$flag_ref" <<<"$arm" && continue
        if grep -qF 'default_branch' <<<"$arm" || grep -qE 'github\.(ref|ref_name|base_ref)' <<<"$arm"; then
          fail "an OR-arm of the test job's gate carries a ref/default-branch predicate without being gated by '$flag_ref', so the new default-branch behaviour reaches consumers that never opted in. Offending arm: ${arm}. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
        fi
      done < <(split_arms "$group")

      # ── 7. The flagged arm must prove the path filter actually RAN ────────────────
      # `changes` is itself gated, so a skipped `changes` job leaves its outputs as the
      # empty string. Without this term the flagged arm would fire on a default-branch run
      # where no filtering happened at all, turning "the suite ran because we checked" into
      # "the suite ran because we could not tell".
      while IFS= read -r arm; do
        grep -qF "$flag_ref" <<<"$arm" || continue
        if ! grep -qF "needs.changes.outputs.go != ''" <<<"$arm"; then
          fail "the '$flag_ref' arm does not require needs.changes.outputs.go != '', so it fires even when the changes job was skipped entirely and no path filtering ever ran — see ksail#6373."
        fi
      done < <(split_arms "$group")
    fi
  fi
fi

# ── 8. The corrected coverage must be what a caller gets by DEFAULT ──────────────────
# Checks 1-7 verify the gate can reach the default-branch run when a caller opts in. They
# say nothing about what a caller who passes NOTHING gets, and that is the property that
# actually decides whether the next consumer inherits the ksail#6373 defect: an input
# defaulting to false makes the vacuous green the paved road and the correct behaviour the
# detour, so every repo onboarded after this workflow starts out reporting a green default
# branch over a suite it never ran.
#
# The rollout this completes is the one the input's own description prescribes — adopt
# caller-by-caller, then flip the default. `ksail` is the only consumer and passes it
# explicitly, so the flip changes no existing caller's behaviour; it changes what a NEW
# caller gets, which is the whole point.
#
# Read through `.on` rather than a grep for `default: true`: the file declares several
# inputs and a textual match cannot attribute a default to the input it belongs to.
default_val="$(yq -r '.on.workflow_call.inputs["'"$flag_input"'"].default' "$workflow" 2>/dev/null || echo "MISSING")"
if [[ "$default_val" == "MISSING" || "$default_val" == "null" ]]; then
  fail "input '$flag_input' has no declared default, so what an unopted caller gets is implicit — see ksail#6373."
elif [[ "$default_val" != "true" ]]; then
  fail "input '$flag_input' defaults to '$default_val', so a caller that passes nothing still decides whether to run the Go suite on its default branch from the diff alone — the exact state ksail#6373 was filed against, now inherited by every new consumer instead of fixed. Flip the default to true (devantler-tech/actions#788 tracks the same flip for scan-default-branch)."
fi

if [[ "$status" -eq 0 ]]; then
  echo "validate-go-project.yaml's test job covers the default branch, and '$flag_input' defaults to on ✅"
fi

exit "$status"
