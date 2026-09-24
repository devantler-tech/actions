// Package main is a self-contained fixture for the govulncheck allowlist
// self-test (the test-govulncheck-* jobs in .github/workflows/ci.yaml). It REACHABLY
// calls a function in a pinned-vulnerable dependency so govulncheck reports a
// known advisory, letting CI prove that validate-go-project.yaml's
// `.govulncheck-allow.txt` allowlist is honored (allowlisted ⇒ pass) and that
// the strict path still blocks (no allow-file ⇒ fail).
//
// Refreshing the fixture: the dependency is PINNED to a vulnerable version on
// purpose, so the advisory is reported regardless of any upstream fix — it does
// not depend on a live advisory staying unpatched. If golang.org/x/text v0.3.0
// or advisory GO-2021-0113 ever stops being reported by govulncheck, repoint
// this module (and the ID in .govulncheck-allow.txt) at another pinned
// dependency version with a known reachable advisory and re-tidy.
//
// CI selects each supported Go toolchain through this module's go directive.
// The scanner is pinned by the shared internal action, never installed at latest.
package main

import (
	"fmt"

	"golang.org/x/text/language"
)

func main() {
	// golang.org/x/text@v0.3.0's BCP 47 parser is subject to GO-2021-0113
	// (index-out-of-range / DoS). Calling language.Parse makes the advisory
	// reachable, so govulncheck reports it as a called vulnerability.
	tag, err := language.Parse("en-US")
	if err != nil {
		fmt.Println("parse error:", err)
		return
	}
	fmt.Println("parsed:", tag)
}
