// Package fixture is a self-contained fixture for the test gate failure-mode
// self-test (the test-validate-go-test-blocks job in
// .github/workflows/ci.yaml). It pairs a trivial function with a deliberately
// failing test (fixture_test.go) so CI can prove validate-go-project.yaml's
// `go test ./...` gate blocks on a failing test.
package fixture

// Add returns the sum of a and b. It exists only so the deliberately failing
// test in fixture_test.go has a real symbol to exercise.
func Add(a, b int) int {
	return a + b
}
