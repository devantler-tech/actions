# Internal fix exporter

The Go workflow's tidy, golangci-lint, and MegaLinter jobs share this composite
action for patch preparation and artifact upload. It holds no branch-write token
and never signs or commits changes. The separate privileged signer consumes the
artifact after the tooling job succeeds.

The caller supplies its existing upload eligibility decision once. That decision
is returned for the caller's read-only failure step. The action retains both
preparation modes: ordinary Go fixes and MegaLinter's opt-in manual recovery for
workflow-file changes. A manual patch stays complete and downloadable; it does not
authorize an automatic signing job.

Reusable workflows resolve this action through their exact-commit checkout at
`.devantler-tech-actions`. The action removes that helper checkout before Git
discovers consumer changes, so source files cannot leak into the patch. Its Bash
body is inline; it does not depend on a script in the removed directory. Direct
repository CI calls leave the repository's own source checkout intact.

## Validation contract

- Preserve invocation-specific artifact names and root-relative binary patches.
- Capture untracked files even when the Go module is nested.
- Preserve whole patches for adds, deletes, renames, mode changes, and mixed fixes.
- Upload only a changed patch from an eligible, uncancelled invocation.
- Preserve opt-in recovery after lint failures without hiding the lint failure.
- Keep forks, dependency-owned branches, disabled signing, and non-PR events read-only.
- Keep both existing signing assertions and the multi-trigger polarity guard green.

The tests execute the actual preparation bodies against disposable Git repositories
and evaluate the actual caller/composite gates. Hosted CI additionally exercises
the composite action, outputs, and artifact transfer through GitHub's runner.
This extraction changes no public workflow input or default.
