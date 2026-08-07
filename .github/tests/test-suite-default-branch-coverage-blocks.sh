#!/usr/bin/env bash
# Failing-input counterpart to test-suite-default-branch-coverage.sh, per the repo
# convention that a gating self-test carries BOTH a passes-on-good-input and a
# blocks-on-bad-input test (AGENTS.md, "Failure-mode coverage for gating workflows").
#
# The guard it exercises is a *gate*: its job is to fail when the `test` job's trigger
# conditions would leave a default branch untested, or would push the new default-branch
# run onto consumers that never opted in. A happy-path test alone cannot catch a guard that
# has silently stopped biting — and this guard is unusually easy to make vacuous, because
# every check is structural string analysis over an expression. A regression in
# `defun`/`strip_groups`/`split_arms`/`outer_group_with` (say, one that makes `$outside`
# always empty, or yields zero arms) would leave every assertion trivially satisfied while
# the positive test stayed green.
#
# Fixtures are GENERATED here from the real workflow rather than committed, so they cannot
# drift from it: each is the real file with `.jobs.test.if` replaced by one deliberately
# wrong gate, composed from the same named clauses as the good one. A fixture therefore
# differs from the good gate ONLY in the defect it is named for. Asserting the *expected
# message* rather than merely a non-zero exit is what stops an operational error (a missing
# yq, a typo'd path) from false-passing as "the gate bit".
#
# Two controls guard the opposite failure — a guard that rejected everything would satisfy
# every assertion above:
#   * the REAL workflow must PASS;
#   * a REFLOWED good gate (same clauses, different wrapping and spacing) must PASS, which
#     proves each rejection is caused by its defect and not by the generation scaffold.

set -euo pipefail

guard="${1:-.github/tests/test-suite-default-branch-coverage.sh}"
workflow="${2:-.github/workflows/validate-go-project.yaml}"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

status=0

# The named clauses the good gate is built from. Every fixture below re-composes THESE, so
# no fixture can differ from the good gate by an accidental typo in a shared part.
REPO="github.repository != 'devantler-tech/reusable-workflows'"
FLAG="(inputs.test-default-branch == true || inputs.test-default-branch == 'true')"
FILTER="needs.changes.outputs.go == 'true'"
RAN="needs.changes.outputs.go != ''"
DB="github.ref == format('refs/heads/{0}', github.event.repository.default_branch)"

GOOD="$REPO && ( $FILTER || ( $FLAG && $RAN && $DB ) )"

# Build a copy of the real workflow whose `test` job carries $2, then run the guard on it.
# `expect_pass` and `expect_block` differ only in the direction asserted, so a control and
# a fixture cannot diverge in how they are evaluated.
run_guard() {
  local name="$1" gate="$2" out rc
  local path="$tmpdir/$name.yaml"
  cp "$workflow" "$path"
  GATE="$gate" yq -i '.jobs.test.if = strenv(GATE)' "$path"
  out="$(bash "$guard" "$path" 2>&1)" && rc=0 || rc=$?
  printf '%s\n' "$out" > "$tmpdir/$name.out"
  return "$rc"
}

expect_block() {
  local name="$1" gate="$2" expected="$3"
  if run_guard "$name" "$gate"; then
    echo "::error::the guard PASSED the deliberately-bad fixture '$name' — it has stopped biting. Expected it to report: $expected"
    status=1
  elif ! grep -qF "$expected" "$tmpdir/$name.out"; then
    echo "::error::fixture '$name' was rejected, but not for the expected reason. Expected a message containing: $expected"
    while IFS= read -r line; do echo "    got: $line"; done < "$tmpdir/$name.out"
    status=1
  else
    echo "blocks $name ✅"
  fi
}

expect_pass() {
  local name="$1" gate="$2"
  if run_guard "$name" "$gate"; then
    echo "passes $name ✅"
  else
    echo "::error::control '$name' was REJECTED, so the guard rejects more than the defect it names — every 'blocks' result above is therefore unattributable."
    while IFS= read -r line; do echo "    got: $line"; done < "$tmpdir/$name.out"
    status=1
  fi
}

# ── Controls: the guard must accept correct input ────────────────────────────────────
if out="$(bash "$guard" "$workflow" 2>&1)"; then
  echo "passes real-workflow ✅"
else
  echo "::error file=$workflow::the guard rejects the REAL workflow, so it is not asserting the shipped gate. Output:"
  while IFS= read -r line; do echo "    got: $line"; done <<<"$out"
  status=1
fi

# The canonical single-line composition of the shared clauses. Every fixture below is built
# from these same five variables, so if this were rejected each "blocks" result would be
# unattributable — the rejection could be the composition rather than the named defect.
expect_pass "good-canonical" "$GOOD"

# Same clauses, different wrapping/spacing. Together with the canonical form above this
# separates "written differently" from "says something different".
expect_pass "good-reflowed" "$REPO
&& (
  $FILTER
  || (
    $FLAG
    && $RAN
    && $DB
  )
)"

# ── 1. The pre-change gate — the state ksail#6373 was filed against ──────────────────
expect_block "original-diff-only" "$REPO && $FILTER" \
  "has no default-branch clause"

# ── 2. Default-branch run not behind the opt-in — a behaviour change for everyone ────
expect_block "no-flag" "$REPO && ( $FILTER || ( $RAN && $DB ) )" \
  "does not reference 'inputs.test-default-branch'"

# ── 3. Flag AND-ed at the top level — a non-opted caller loses the job entirely ──────
expect_block "flag-top-level-bare" "$REPO && inputs.test-default-branch == true && ( $FILTER || ( $RAN && $DB ) )" \
  "OUTSIDE the OR-group"

# The same defect wearing parentheses, AND still correctly placed inside the arm-group.
# This is the arm that earns the guard's containment test, and it is a narrower shape than
# it first appears — verified by ablation rather than assumed:
#
#   * `flag-top-level-bare` above is caught by a `strip_groups`-based check too, because a
#     bare conjunct survives group deletion;
#   * a parenthesised top-level flag that was REMOVED from the arm-group is also still
#     caught — by checks 5 and 6, which notice the group has lost its flagged arm;
#   * only this shape — parenthesised at the top level while the arm-group remains
#     well-formed — defeats every other check. `strip_groups` erases the conjunct along
#     with every legitimate group, checks 5-7 all pass because the arm-group really is
#     correct, and the guard reports a gate that has silently removed the test job from
#     every consumer that never opted in.
#
# Hence the guard asks "is the flag inside the arm-group?" (containment) instead of
# deleting parenthesised text and inspecting what is left.
expect_block "flag-top-level-and-in-group" "$REPO && $FLAG && ( $FILTER || ( $FLAG && $RAN && $DB ) )" \
  "OUTSIDE the OR-group"

# ── 4. Path filter AND-ed at the top level — the default-branch arm is decorative ────
expect_block "filter-top-level" "$REPO && $FILTER && ( $FLAG && $RAN && $DB )" \
  "AND-s the path filter"

# ── 4b. The base diff-trigger dropped entirely — opt-in-only execution ───────────────
# The subtlest defect modelled here, and the one that motivated check 4b. The group still
# contains a `||` — but only the one inside the flag's own `== true || == 'true'`
# normalisation — so a `||`-presence test reports the base trigger as OR-ed when the
# group's top level is in fact a pure conjunction. Every consumer that does not opt in
# silently loses its diff-triggered test run, which is precisely the backward-compatibility
# property this guard claims to protect. Verified to pass the guard before check 4b existed.
expect_block "base-arm-dropped" "$REPO && ( $FLAG && $RAN && $DB )" \
  "no top-level OR-arm of the group is exactly"

# ── 5. A single event gating the whole job — no opt-in can reach the default branch ──
expect_block "top-level-event" "$REPO && github.event_name == 'pull_request' && ( $FILTER || ( $FLAG && $RAN && $DB ) )" \
  "AND-s 'github.event_name ==' at the top level"

# ── 6. A top-level ref predicate excluding the very branch the new arm targets ───────
expect_block "top-level-ref" "$REPO && github.ref != 'refs/heads/main' && ( $FILTER || ( $FLAG && $RAN && $DB ) )" \
  "AND-s a top-level ref predicate"

# ── 7. The flag gates something OTHER than the default-branch clause ─────────────────
# Referenced (so check 3 is satisfied) and a default-branch clause exists (check 2), but
# they live in different arms — so opting in does not buy the default-branch run.
expect_block "flag-arm-lacks-default-branch" "$REPO && ( $FILTER || ( $FLAG && $RAN ) || ( $RAN && $DB ) )" \
  "no OR-arm both references"

# ── 8. An unflagged arm that widens — new behaviour without opting in ────────────────
expect_block "unflagged-arm-widens" "$REPO && ( $FILTER || ( $RAN && $DB ) || ( $FLAG && $RAN && $DB ) )" \
  "without being gated by"

# ── 9. The flagged arm fires without proof the filter ever ran ───────────────────────
# `changes` is itself gated; when it is skipped its outputs are the empty string. Dropping
# the `!= ''` term turns "the suite ran because we checked the diff" into "the suite ran
# because we could not tell", which is a different guarantee wearing the same green tick.
expect_block "flagged-arm-lacks-ran-proof" "$REPO && ( $FILTER || ( $FLAG && $DB ) )" \
  "does not require needs.changes.outputs.go != ''"

# ── 10. The input's DEFAULT, which no gate fixture can reach ─────────────────────────
# Every fixture above rewrites `.jobs.test.if`, so none of them can exercise check 8 —
# that check reads the input's declared default, not the gate. Without these two the flip
# to `default: true` would be unguarded: someone could set it back to false, all nine
# assertions above would still pass, and the guard would report full default-branch
# coverage over a workflow whose next consumer silently inherits the ksail#6373 defect.
#
# The gate is held at the KNOWN-GOOD expression throughout, so the only thing that differs
# from a passing run is the default itself — which is what makes the rejection attributable
# to check 8 rather than to some incidental malformation.
run_guard_default() {
  local name="$1" out rc
  local path="$tmpdir/$name.yaml"
  cp "$workflow" "$path"
  GATE="$GOOD" yq -i '.jobs.test.if = strenv(GATE)' "$path"
  case "$2" in
    MISSING) yq -i 'del(.on.workflow_call.inputs["test-default-branch"].default)' "$path" ;;
    *)       VAL="$2" yq -i '.on.workflow_call.inputs["test-default-branch"].default = (strenv(VAL) == "true")' "$path" ;;
  esac
  out="$(bash "$guard" "$path" 2>&1)" && rc=0 || rc=$?
  printf '%s\n' "$out" > "$tmpdir/$name.out"
  return "$rc"
}

expect_block_default() {
  local name="$1" val="$2" expected="$3"
  if run_guard_default "$name" "$val"; then
    echo "::error::the guard PASSED the deliberately-bad fixture '$name' (default=$val) — check 8 has stopped biting. Expected it to report: $expected"
    status=1
  elif ! grep -qF "$expected" "$tmpdir/$name.out"; then
    echo "::error::fixture '$name' was rejected, but not for the expected reason. Expected a message containing: $expected"
    while IFS= read -r line; do echo "    got: $line"; done < "$tmpdir/$name.out"
    status=1
  else
    echo "blocks $name ✅"
  fi
}

# The pre-flip state: opt-in, so a new consumer inherits the vacuous green.
expect_block_default "default-false" "false" "defaults to 'false'"

# No default at all — what an unopted caller gets becomes implicit rather than declared.
expect_block_default "default-missing" "MISSING" "has no declared default"

# Control for the pair above: same scaffold, correct default, must PASS. Without this a
# `run_guard_default` that corrupted the file would make both rejections unattributable.
if run_guard_default "default-true-control" "true"; then
  echo "passes default-true-control ✅"
else
  echo "::error::control 'default-true-control' was REJECTED, so the default-fixture scaffold itself breaks the workflow — both 'blocks' results above are unattributable."
  while IFS= read -r line; do echo "    got: $line"; done < "$tmpdir/default-true-control.out"
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "test-suite-default-branch-coverage.sh bites on every modelled defect ✅"
fi

exit "$status"
