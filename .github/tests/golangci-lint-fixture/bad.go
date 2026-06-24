// Package fixture is a self-contained fixture for the golangci-lint gate
// failure-mode self-test (the test-validate-go-lint-blocks job in
// .github/workflows/ci.yaml). It contains a deliberate, NON-auto-fixable lint
// violation — an unchecked error return, flagged by errcheck — so golangci-lint
// exits non-zero and CI can prove validate-go-project.yaml's golangci-lint gate
// blocks on a lint violation.
//
// Why errcheck specifically: it has no autofixer, so the gate's `--fix` args
// cannot silently rewrite the finding away — golangci-lint reports it and exits
// non-zero directly, which is exactly the gate's "lint fails the build" block
// path. .golangci.yaml pins the linter set to errcheck only, so the finding is
// reported regardless of golangci-lint's evolving defaults.
//
// Refreshing the fixture: if errcheck ever stops flagging an unchecked error,
// repoint .golangci.yaml at another default, non-auto-fixable linter and add a
// matching violation here, then update the linter name asserted in the
// test-validate-go-lint-blocks job.
package fixture

import "os"

// Bad ignores the error returned by os.Setenv, which errcheck flags as
// "Error return value of `os.Setenv` is not checked". The assignment is a bare
// statement (not `_ =`), so errcheck does not treat it as an explicit ignore.
func Bad() {
	os.Setenv("GOLANGCI_LINT_FIXTURE", "1")
}
