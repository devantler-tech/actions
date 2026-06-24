// Package main is a minimal, valid Go module used as the known-good fixture
// for the validate-go-project workflow's happy-path self-test. It must pass
// every gate (build, test, tidy, deadcode, govulncheck, golangci-lint,
// mega-linter), so keep it trivial and dependency-free.
package main

func add(a, b int) int {
	return a + b
}

func main() {
	_ = add(2, 3)
}
