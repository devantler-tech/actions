#!/usr/bin/env bash

# Every automated commit this org's shared workflows produce must be signed.
#
# Unsigned automation commits are not broken today — what lands on a default branch is a
# GitHub-created squash commit, which is signed regardless. The cost is optionality:
# commit-signature verification cannot be REQUIRED on branches while any write lane would
# be refused by it, so the strongest form of that control stays permanently out of reach
# (devantler-tech/.github#142).
#
# Two mechanisms produce commits here, and they are checked differently:
#
#   * `peter-evans/create-pull-request` commits locally by default. Its `sign-commits: true`
#     option makes it commit through the GitHub API instead, and GitHub signs a commit an
#     App or Actions token creates when the request carries no custom author/committer or
#     signature fields.
#   * `stefanzweifel/git-auto-commit-action` has no such option — it can only run a local
#     `git commit`, so its output is unsigned unless a signing key is configured on the
#     runner. The fixer lanes migrated off it (#1005, #1011, #1036) onto the shared
#     `apply-signed-fixes.yaml`; this test keeps them off it.

# SCOPE: reusable workflows only. Verified when this test was written that no composite
# action or script in this repository produces a commit, so `.github/workflows` is the
# complete set of producers. If a composite action ever commits, widen this scan — the
# assertions below cannot see outside `workflow_dir`.

set -euo pipefail

workflow_dir="${1:-.github/workflows}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -d "$workflow_dir" ]] || fail "workflow directory '$workflow_dir' does not exist"
command -v yq >/dev/null || fail "yq is unavailable"

cpr_total=0
cpr_unsigned=()
auto_commit=()

# NOTE: a `while read` loop in a pipeline runs in a subshell under some shells, losing every
# variable it sets — collect the file list first and feed it in on stdin instead.
workflows=()
while IFS= read -r wf; do
  [[ -n "$wf" ]] || continue
  workflows+=("$wf")
done <<<"$(find "$workflow_dir" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) | sort)"
((${#workflows[@]} > 0)) || fail "no workflow files found under '$workflow_dir'"

for wf in "${workflows[@]}"; do
  count="$(
    yq -r '[.jobs[]?.steps[]? | select((.uses // "") | test("^peter-evans/create-pull-request@"))] | length' "$wf"
  )" || fail "could not parse '$wf'"
  cpr_total=$((cpr_total + count))

  if [[ "$count" != "0" ]]; then
    unsigned="$(
      yq -r '
        [.jobs[]?.steps[]?
         | select((.uses // "") | test("^peter-evans/create-pull-request@"))
         | select((.with."sign-commits" // false) != true)
         | (.name // .id // .uses)]
        | .[]' "$wf"
    )" || fail "could not parse '$wf'"
    while IFS= read -r step; do
      [[ -n "$step" ]] || continue
      cpr_unsigned+=("$wf :: $step")
    done <<<"$unsigned"
  fi

  gac="$(
    yq -r '[.jobs[]?.steps[]? | select((.uses // "") | test("^stefanzweifel/git-auto-commit-action@"))] | length' "$wf"
  )" || fail "could not parse '$wf'"
  [[ "$gac" == "0" ]] || auto_commit+=("$wf ($gac step(s))")
done

# Positive control. Without it, renaming or dropping the action makes the signing assertion
# above match nothing and pass vacuously — an empty filtered read is a claim about the
# filter, not about the repository. If create-pull-request is deliberately retired, update
# this test to cover whatever replaced it rather than deleting the control.
((cpr_total > 0)) ||
  fail "no peter-evans/create-pull-request steps found under '$workflow_dir' — the signing assertion would pass vacuously; update this test to match the mechanism now in use"

if ((${#cpr_unsigned[@]} > 0)); then
  printf 'FAIL: these create-pull-request steps commit locally and produce UNSIGNED commits.\n' >&2
  printf '      Add sign-commits: true so the commit is made through the GitHub API and signed:\n' >&2
  printf '        - %s\n' "${cpr_unsigned[@]}" >&2
  exit 1
fi

if ((${#auto_commit[@]} > 0)); then
  printf 'FAIL: git-auto-commit-action cannot produce a signed commit; use the shared\n' >&2
  printf '      apply-signed-fixes.yaml workflow instead:\n' >&2
  printf '        - %s\n' "${auto_commit[@]}" >&2
  exit 1
fi

echo "PASS: all $cpr_total create-pull-request step(s) sign their commits, and no workflow commits with git-auto-commit-action"
