package fixture

import "testing"

// TestDeliberatelyFails ALWAYS fails on purpose: it asserts a result that is
// known to be wrong (2 + 2 == 5). The test gate self-test
// (test-validate-go-test-blocks in .github/workflows/ci.yaml) runs
// `go test ./...` on this fixture and asserts it exits non-zero AND that this
// test reported "--- FAIL", proving validate-go-project.yaml's test gate blocks
// on a failing test rather than silently passing. Do not "fix" this test.
func TestDeliberatelyFails(t *testing.T) {
	if got := Add(2, 2); got != 5 {
		t.Fatalf("deliberate failing test for the go-test gate self-test: Add(2, 2) = %d", got)
	}
}
