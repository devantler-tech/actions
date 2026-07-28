#!/usr/bin/env bash
# Guards the govulncheck job's TRIGGER conditions in validate-go-project.yaml
# (devantler-tech/ksail#6373).
#
# A vulnerability scan's verdict depends on the vulnerability DATABASE as well as the
# diff: an advisory published after a merge makes unchanged, already-merged code
# vulnerable. Any trigger condition that ties the scan to the shape of a diff, or to a
# single event, therefore lets a Go repo's default branch report green while it is in
# fact unscanned. Three such conditions are asserted against here:
#
#   1. An `event_name` equality on the job (it carried `== 'pull_request'`), which meant
#      the scan never ran on the default branch at all. Measured on ksail: GO-2026-6061
#      (reachable, google.golang.org/grpc < v1.82.1) was published 2026-07-27T15:30Z
#      against a pinned dependency main already had, and main kept reporting green.
#
#   2. The path filter left as the only gate on the default branch. A default-branch push
#      that touches no Go path — a README edit — leaves `needs.changes.outputs.go` false
#      and skips the scan, so a newly-published advisory goes unreported until the next
#      Go change happens to land.
#
#   3. `.govulncheck-allow.txt` missing from the `go` path filter, so a commit whose ONLY
#      purpose is to change which advisories the gate accepts skipped the gate that reads
#      it. Measured on ksail commit c3522e89 (a `.govulncheck-allow.txt`-only push to
#      main): `🛡️ Vulnerability Scan` → skipped. The nested form matters too, because
#      `working-directory` may point at a module whose allowlist is not at the repo root.
#
# These are asserted POSITIVELY — the intended condition must be present — rather than by
# rejecting one known-bad string. A test that only rejects `event_name == 'pull_request'`
# still passes if the job is restricted some other way (a different event equality, or a
# ref predicate that excludes the default branch), and would then claim default-branch
# coverage over a workflow that never scans it.

set -euo pipefail

workflow="${1:-.github/workflows/validate-go-project.yaml}"

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

if [[ -z "$gate" || "$gate" == "null" ]]; then
  fail "govulncheck job has no 'if:' gate to verify"
else
  normalized="$(defun "$flat")"
  top_level="$(strip_groups "$normalized")"

  # ── 1. The scan must not be restricted to any single event ──────────────────────
  # Deliberately matches ANY event_name equality, not just 'pull_request': the defect is
  # "this scan only runs for one kind of run", and every spelling of that has the same
  # consequence on the default branch.
  if grep -qE "github\.event_name[[:space:]]*==" <<<"$flat"; then
    fail "govulncheck's gate restricts by 'github.event_name ==', so whole classes of run — including the default branch — can never scan. A vulnerability scan's verdict depends on the vulnerability database, not only on the diff. Remove the event equality; see ksail#6373."
  fi

  # ── 2. A default-branch run must scan regardless of the diff ────────────────────
  if ! grep -qF 'default_branch' <<<"$flat"; then
    fail "govulncheck's gate has no default-branch clause, so the path filter is the only gate on the default branch and a non-Go push (e.g. a README edit) leaves it unscanned while reporting green. Add: || github.ref == format('refs/heads/{0}', github.event.repository.default_branch) — see ksail#6373."
  fi

  # ── 3. The path filter must not be able to veto a default-branch run ────────────
  # The diff gate has to sit inside an OR-group with the default-branch clause. If it is
  # a top-level conjunct instead, the default-branch clause is decorative: `go == 'true'`
  # still has to hold, which is exactly the state check 2 exists to prevent.
  if grep -qF 'needs.changes.outputs.go' <<<"$top_level"; then
    fail "govulncheck AND-s the path filter (needs.changes.outputs.go) at the top level, so a default-branch run with no Go paths changed is still skipped. The path filter must be OR-ed with the default-branch clause, not AND-ed alongside it — see ksail#6373."
  elif grep -qE 'github\.(ref|ref_name|head_ref|base_ref)' <<<"$top_level"; then
    # The legitimate default-branch clause lives inside the OR-group and has already been
    # stripped by now, so any ref predicate still standing here is an ADDITIONAL top-level
    # conjunct. `&& github.ref != 'refs/heads/main'` would satisfy checks 1-3 while making
    # default-branch runs unreachable — the state this file exists to prevent, and the one
    # its own header claims to catch.
    fail "govulncheck AND-s a top-level ref predicate, which can exclude the default branch no matter what the OR-ed default-branch clause says. A ref condition belongs inside that OR-group, not alongside it — see ksail#6373."
  else
    # Extract the OUTERMOST parenthesised group containing the path-filter term, by
    # balance-scanning rather than by regex. A regex bounded with `[^()]*` can only match a
    # group with no nesting, so it silently returns the INNERMOST group — and the gate's
    # OR-arm may legitimately nest (`(go=='true' || (go=='false' && ref==...))`), whose
    # inner group holds no `||` and would be misreported as "grouped but not OR-ed".
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
    fi
  fi
fi

# ── 4. Editing the allowlist must re-run the scan that consumes it ────────────────
# Read the filter as text: the `filters:` value is a YAML string block handed to
# dorny/paths-filter, so it is not addressable as structured YAML from here.
filters="$(yq -r '.jobs.changes.steps[] | select(.id == "filter") | .with.filters // ""' "$workflow")"
if [[ -z "$filters" || "$filters" == "null" ]]; then
  fail "could not read the paths-filter 'filters' block"
else
  # Take the `go:` filter only — up to the next top-level filter key — so a match under
  # some other filter (e.g. `lintable:`) cannot false-pass this assertion.
  go_filter="$(awk '/^go:/{f=1;next} /^[a-zA-Z_-]+:/{f=0} f' <<<"$filters")"
  if ! grep -qF "'.govulncheck-allow.txt'" <<<"$go_filter"; then
    fail "the 'go' path filter omits '.govulncheck-allow.txt', so a commit that only edits the allowlist skips the vulnerability scan that reads it — see ksail#6373."
  fi
  # `working-directory` may select a nested module, whose allowlist is not at the root.
  if ! grep -qF "'**/.govulncheck-allow.txt'" <<<"$go_filter"; then
    fail "the 'go' path filter omits '**/.govulncheck-allow.txt', so an allowlist edit inside a nested module selected by 'working-directory' (e.g. services/api/.govulncheck-allow.txt) skips the scan that reads it — see ksail#6373."
  fi
fi

if [[ "$status" -eq 0 ]]; then
  echo "govulncheck scans every default-branch run and is triggered by allowlist edits ✅"
fi

exit "$status"
