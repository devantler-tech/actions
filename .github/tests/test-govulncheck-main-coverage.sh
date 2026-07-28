#!/usr/bin/env bash
# Guards the govulncheck job's TRIGGER conditions in validate-go-project.yaml
# (devantler-tech/ksail#6373).
#
# A vulnerability scan's verdict depends on the vulnerability DATABASE as well as the
# diff: an advisory published after a merge makes unchanged, already-merged code
# vulnerable. Any trigger condition that ties the scan to the shape of a diff, or to a
# single event, therefore lets a Go repo's default branch report green while it is in
# fact unscanned. Measured on ksail: GO-2026-6061 (reachable, google.golang.org/grpc
# < v1.82.1) was published 2026-07-27T15:30Z against a pinned dependency main already
# had, and main kept reporting green.
#
# Fixing that changes behaviour in every consumer repo at once, so the default-branch
# scan ships behind the opt-in input `scan-default-branch` (AGENTS.md, *Shipping a new
# capability behind an opt-in flag*). That makes the gate a two-armed expression, and
# this guard asserts the shape of BOTH arms:
#
#   * the flagged arm must actually be reachable — the default-branch clause OR-ed with
#     the diff gate, not AND-ed alongside it, and no top-level predicate able to veto it;
#   * the unflagged arm must not have grown — anything reachable WITHOUT the opt-in has
#     to stay restricted to pull requests, which is what makes the change backward
#     compatible for a caller that passes nothing.
#
# Everything is asserted POSITIVELY — the intended property must hold — rather than by
# rejecting one known-bad string. A test that only rejects `event_name == 'pull_request'`
# still passes if the job is restricted some other way (a different event equality, or a
# ref predicate that excludes the default branch), and would then claim default-branch
# coverage over a workflow that never scans it.
#
# The allowlist trigger is asserted in both directions for the same reason: it must be
# present (a commit that changes which advisories are accepted has to re-run the scan
# that reads them), and it must NOT live in the shared `go` filter (which would make an
# administrative allowlist edit run tidy, golangci-lint, deadcode, the test matrix and
# coverage in every consumer, so an unrelated pre-existing failure could block it).

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"

flag_input="scan-default-branch"
flag_ref="inputs.${flag_input}"

status=0

fail() {
  echo "::error file=$workflow::$1"
  status=1
}

# Collapse the gate to one whitespace-normalised line so the structural checks below do
# not depend on how the YAML block scalar happens to be wrapped.
gate="$(yq -r '.jobs.govulncheck.if // ""' "$workflow")"
flat="$(tr '\n' ' ' <<<"$gate" | tr -s ' ')"

# Rewrite function-call parentheses — `format('refs/heads/{0}', x)` — into angle brackets,
# preserving their contents. Without this the call's parens are indistinguishable from
# grouping parens, which both hides the real group and makes `default_branch` (an argument
# to such a call) impossible to attribute to the group it actually guards.
defun() {
  local s="$1" prev=""
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="$(sed -E 's/([A-Za-z_][A-Za-z0-9_.]*)\(([^()]*)\)/\1<\2>/g' <<<"$s")"
  done
  printf '%s' "$s"
}

# Repeatedly delete innermost parenthesised groups, leaving only the top-level conjuncts.
# A term that survives this is AND-ed at the top level and can therefore veto the job on
# its own, whatever else the gate says.
strip_groups() {
  local s="$1" prev=""
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="$(sed -E 's/\([^()]*\)/ /g' <<<"$s")"
  done
  printf '%s' "$s"
}

# Split a parenthesised group into its top-level `||` arms, one per line. Balance-scanned
# rather than split on `||`, because an arm may itself contain a parenthesised `||` (both
# arms of this gate do).
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

if [[ -z "$gate" || "$gate" == "null" ]]; then
  fail "govulncheck job has no 'if:' gate to verify"
else
  normalized="$(defun "$flat")"
  top_level="$(strip_groups "$normalized")"

  # ── 1. No single event may gate the whole job ───────────────────────────────────
  # Scoped to the TOP LEVEL. An event equality inside the unflagged arm is legitimate and
  # in fact required by check 6 — it is what keeps that arm restricted to pull requests.
  # A top-level one is the original defect: it vetoes every arm, so no opt-in can reach
  # the default-branch scan.
  if grep -qE "github\.event_name[[:space:]]*==" <<<"$top_level"; then
    fail "govulncheck AND-s 'github.event_name ==' at the top level, so whole classes of run — including the default branch — can never scan, whatever the opt-in input says. A vulnerability scan's verdict depends on the vulnerability database, not only on the diff. An event equality belongs inside an OR-arm, not alongside it; see ksail#6373."
  fi

  # ── 2. A default-branch run must be able to scan regardless of the diff ─────────
  if ! grep -qF 'default_branch' <<<"$flat"; then
    fail "govulncheck's gate has no default-branch clause, so the path filter is the only gate on the default branch and a non-Go push (e.g. a README edit) leaves it unscanned while reporting green. Add: || github.ref == format('refs/heads/{0}', github.event.repository.default_branch) — see ksail#6373."
  fi

  # ── 3. The opt-in input must gate the new capability, not the whole job ─────────
  if ! grep -qF "$flag_ref" <<<"$flat"; then
    fail "govulncheck's gate does not reference '$flag_ref', so the default-branch scan is not behind the opt-in input it is required to ship behind — a behaviour change landing on every consumer at once. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
  elif grep -qF "$flag_ref" <<<"$top_level"; then
    fail "govulncheck AND-s '$flag_ref' at the top level, so a caller that does not opt in loses the pull-request scan it has today. The input must gate the default-branch arm only — see AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
  fi

  # ── 4. The path filter must not be able to veto a default-branch run ───────────
  # The diff gate has to sit inside an OR-group with the default-branch clause. If it is
  # a top-level conjunct instead, the default-branch clause is decorative: `go == 'true'`
  # still has to hold, which is exactly the state check 2 exists to prevent.
  if grep -qF 'needs.changes.outputs.go' <<<"$top_level"; then
    fail "govulncheck AND-s the path filter (needs.changes.outputs.go) at the top level, so a default-branch run with no Go paths changed is still skipped. The path filter must be OR-ed with the default-branch clause, not AND-ed alongside it — see ksail#6373."
  elif grep -qE 'github\.(ref|ref_name|head_ref|base_ref)' <<<"$top_level"; then
    # The legitimate default-branch clause lives inside the OR-group and has already been
    # stripped by now, so any ref predicate still standing here is an ADDITIONAL top-level
    # conjunct. `&& github.ref != 'refs/heads/main'` would satisfy the checks above while
    # making default-branch runs unreachable — the state this file exists to prevent, and
    # the one its own header claims to catch.
    fail "govulncheck AND-s a top-level ref predicate, which can exclude the default branch no matter what the OR-ed default-branch clause says. A ref condition belongs inside that OR-group, not alongside it — see ksail#6373."
  else
    # Extract the OUTERMOST parenthesised group containing the path-filter term, by
    # balance-scanning rather than by regex. A regex bounded with `[^()]*` can only match a
    # group with no nesting, so it silently returns the INNERMOST group — and both arms of
    # this gate legitimately nest, whose inner groups hold no top-level `||`.
    group="$(awk '
      { s = $0; depth = 0; start = 0
        for (i = 1; i <= length(s); i++) {
          c = substr(s, i, 1)
          if (c == "(") { if (depth == 0) start = i; depth++ }
          else if (c == ")") {
            depth--
            if (depth == 0 && start > 0) {
              g = substr(s, start, i - start + 1)
              if (index(g, "needs.changes.outputs.go") > 0) { print g; exit }
            }
          }
        }
      }' <<<"$normalized" || true)"
    if [[ -z "$group" ]]; then
      fail "could not find the parenthesised group holding the path-filter term; the gate's structure is not what this guard can verify — see ksail#6373."
    elif ! grep -qF 'default_branch' <<<"$group"; then
      fail "the path-filter term is grouped, but not with the default-branch clause, so a default-branch run with no Go paths changed is still skipped — see ksail#6373."
    elif ! grep -qF '||' <<<"$group"; then
      fail "the path-filter term and the default-branch clause share a group but are not OR-ed, so the default-branch clause cannot rescue a run the path filter rejected — see ksail#6373."
    else
      # ── 5. The default-branch clause must sit in the arm the input gates ────────
      # Otherwise the input is referenced (check 3) but guards something else, and the new
      # scan is reachable without opting in.
      flagged_arm_has_default_branch=0
      while IFS= read -r arm; do
        if grep -qF "$flag_ref" <<<"$arm" && grep -qF 'default_branch' <<<"$arm"; then
          flagged_arm_has_default_branch=1
        fi
      done < <(split_arms "$group")
      if [[ "$flagged_arm_has_default_branch" -eq 0 ]]; then
        fail "no OR-arm both references '$flag_ref' and carries the default-branch clause, so the default-branch scan is not the thing the opt-in input actually gates. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
      fi

      # ── 6. Nothing new may run without opting in ────────────────────────────────
      # This is the backward-compatibility property, asserted directly: every arm that the
      # input does NOT gate must still be restricted to pull requests, so a caller that
      # passes nothing gets exactly the behaviour it has today. Without this an arm could
      # be added that fires on pushes for everyone, and checks 1-5 would all still pass.
      while IFS= read -r arm; do
        [[ -n "${arm// /}" ]] || continue
        grep -qF "$flag_ref" <<<"$arm" && continue
        if ! grep -qE "github\.event_name[[:space:]]*==[[:space:]]*'pull_request'" <<<"$arm"; then
          fail "an OR-arm of govulncheck's gate is neither gated by '$flag_ref' nor restricted to pull requests, so it runs for every consumer that never opted in. Offending arm: ${arm}. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
        fi
      done < <(split_arms "$group")
    fi
  fi
fi

# ── 7. The opt-in input must exist and default to OFF ─────────────────────────────
# A flag declared with `default: true` is not an opt-in; it is the unflagged rollout
# wearing an input's clothes.
# NB: no `// ""` fallback on these reads. yq's alternative operator treats a literal
# `false` as absent, so `.default // ""` on the correctly-configured input returns the
# empty string and this check would reject exactly the state it is meant to accept.
input_type="$(yq -r ".[\"on\"].workflow_call.inputs.\"${flag_input}\".type" "$workflow")"
input_default="$(yq -r ".[\"on\"].workflow_call.inputs.\"${flag_input}\".default" "$workflow")"
if [[ -z "$input_type" || "$input_type" == "null" ]]; then
  fail "workflow_call declares no '${flag_input}' input, so callers cannot opt in to the default-branch scan and the gate's reference to it is dead. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
elif [[ "$input_type" != "boolean" ]]; then
  fail "the '${flag_input}' input is type '${input_type}', not boolean. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
elif [[ "$input_default" != "false" ]]; then
  fail "the '${flag_input}' input defaults to '${input_default}', not false — so it is not opt-in and the default-branch scan lands on every consumer the moment this merges. See AGENTS.md, 'Shipping a new capability behind an opt-in flag'."
fi

# ── 8. Editing the allowlist must re-run the scan that consumes it ────────────────
# Read the filter as text: the `filters:` value is a YAML string block handed to
# dorny/paths-filter, so it is not addressable as structured YAML from here.
filters="$(yq -r '.jobs.changes.steps[] | select(.id == "filter") | .with.filters // ""' "$workflow")"
if [[ -z "$filters" || "$filters" == "null" ]]; then
  fail "could not read the paths-filter 'filters' block"
else
  # Drop comment lines before sectioning: a comment that mentions a pattern must not be
  # able to satisfy — or trip — an assertion about which filter actually lists it.
  filter_body="$(grep -v '^[[:space:]]*#' <<<"$filters" || true)"
  # Take one filter's entries only — up to the next top-level filter key — so a match
  # under a different filter cannot false-pass.
  section() { awk -v key="$1" '$0 ~ "^" key ":" {f=1;next} /^[a-zA-Z_-]+:/{f=0} f' <<<"$filter_body"; }
  go_filter="$(section go)"
  vuln_filter="$(section govulncheck)"

  if ! grep -qF "'.govulncheck-allow.txt'" <<<"$vuln_filter"; then
    fail "the 'govulncheck' path filter omits '.govulncheck-allow.txt', so a commit that only edits the allowlist skips the vulnerability scan that reads it — see ksail#6373."
  fi
  # `working-directory` may select a nested module, whose allowlist is not at the root.
  if ! grep -qF "'**/.govulncheck-allow.txt'" <<<"$vuln_filter"; then
    fail "the 'govulncheck' path filter omits '**/.govulncheck-allow.txt', so an allowlist edit inside a nested module selected by 'working-directory' (e.g. services/api/.govulncheck-allow.txt) skips the scan that reads it — see ksail#6373."
  fi
  # The other direction: the allowlist must NOT widen the shared `go` output, which
  # go-mod-tidy, golangci-lint, deadcode, the test matrix and coverage all consume.
  if grep -qF '.govulncheck-allow.txt' <<<"$go_filter"; then
    fail "the shared 'go' path filter lists '.govulncheck-allow.txt', so an allowlist-only commit sets needs.changes.outputs.go and runs go-mod-tidy, golangci-lint, deadcode, the test matrix and coverage in every consumer repo — an administrative risk-acceptance could then be blocked by an unrelated pre-existing failure. Keep the allowlist in its own 'govulncheck' filter, OR-ed into the govulncheck job alone."
  fi
  # The dedicated output is only useful if the job actually consults it.
  if ! grep -qF 'needs.changes.outputs.govulncheck' <<<"$flat"; then
    fail "the 'govulncheck' filter output is never read by the govulncheck job's gate, so an allowlist-only commit still skips the scan. OR it into the pull-request arm."
  fi
  if [[ -z "$(yq -r '.jobs.changes.outputs.govulncheck // ""' "$workflow")" ]]; then
    fail "the 'changes' job does not expose a 'govulncheck' output, so needs.changes.outputs.govulncheck is always empty and the allowlist trigger silently never fires."
  fi
fi

if [[ "$status" -eq 0 ]]; then
  echo "govulncheck's default-branch scan is opt-in and reachable, nothing new runs unopted, and allowlist edits trigger the scan that reads them ✅"
fi

exit "$status"
