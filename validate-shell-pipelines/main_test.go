package main

import "testing"

// TestPipelineSyntax distinguishes executable consumers from quotes, wrappers, and operands.
func TestPipelineSyntax(t *testing.T) {
	cases := []struct{ name, source, flag string }{
		{"cluster", "producer | grep -Fqn needle", "-q"},
		{"quiet long", "producer | grep --quiet needle", "--quiet"},
		{"silent", "producer | grep --silent needle", "--silent"},
		{"filenames", "producer | grep -l needle", "-l"},
		{"filenames long", "producer | grep --files-with-matches needle", "--files-with-matches"},
		{"max attached", "producer | grep -Fm1 needle", "-m"},
		{"max separate", "producer | grep -m 1 needle", "-m"},
		{"max long", "producer | grep --max-count=1 needle", "--max-count"},
		{"late option", "producer | grep needle -q", "-q"},
		{"command", "producer | command -p /usr/bin/grep -q needle", "-q"},
		{"env", "producer | env -i -u HOME LC_ALL=C grep -q needle", "-q"},
		{"assign", "producer | LC_ALL=C grep -q needle", "-q"},
		{"quoted command", "producer | 'gr'\"ep\" '-q' needle", "-q"},
		{"escaped command", "producer | gr\\ep -q needle", "-q"},
		{"stderr pipe", "producer |& grep -q needle", "-q"},
		{"negation", "! producer | grep -q needle", "-q"},
		{"substitution", "result=$(producer | grep -q needle)", "-q"},
		{"subshell", "producer | (grep -q needle)", "-q"},
		{"block", "producer | { grep -q needle; }", "-q"},
		{"continuation", "producer | \\\n grep \\\n -q needle", "-q"},
		{"pipeline middle", "producer | grep -q needle | consumer", "-q"},
		{"plain", "producer | grep needle", ""},
		{"count", "producer | grep -c needle", ""},
		{"nonmatching filenames", "producer | grep -L needle", ""},
		{"pattern", "producer | grep -- -q", ""},
		{"regexp", "producer | grep -e -q", ""},
		{"regexp attached", "producer | grep -Feq", ""},
		{"pattern file", "producer | grep -f -q", ""},
		{"long regexp", "producer | grep --regexp=-q", ""},
		{"unlimited", "producer | grep -m -1 needle", ""},
		{"lookup", "producer | command -v grep -q", ""},
		{"file input", "grep -q needle capture.txt", ""},
		{"literal", "printf '%s' 'producer | grep -q needle'", ""},
		{"comment", "# producer | grep -q needle", ""},
		{"heredoc", "cat <<'DOC'\nproducer | grep -q needle\nDOC\n", ""},
		{"heredoc expansion", "cat <<DOC\n$(producer | grep -q needle)\nDOC\n", "-q"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := scanSource("fixture.sh", []byte(tc.source+"\n"))
			if err != nil {
				t.Fatal(err)
			}
			if tc.flag == "" {
				if len(got) != 0 {
					t.Fatalf("safe syntax reported: %+v", got)
				}
				return
			}
			if len(got) != 1 || got[0].flag != tc.flag {
				t.Fatalf("want %q, got %+v", tc.flag, got)
			}
		})
	}
}

// TestCommentExceptions confines exemptions to real comments with an explicit reason.
func TestCommentExceptions(t *testing.T) {
	cases := []struct {
		name, source string
		count        int
		bad          bool
	}{
		{"inline", "producer | grep -q needle # pipefail-grep-guard: allow fixture demonstrates SIGPIPE\n", 0, false},
		{"file", "# pipefail-grep-guard: allow-file negative fixture\nproducer | grep -q needle\n", 0, false},
		{"unrelated line", "# pipefail-grep-guard: allow unrelated\nproducer | grep -q needle\n", 1, false},
		{"quoted spoof", "producer | grep -q 'pipefail-grep-guard: allow fake'\n", 1, false},
		{"heredoc spoof", "cat <<'DOC'\n# pipefail-grep-guard: allow-file fake\nDOC\nproducer | grep -q needle\n", 1, false},
		{"reason missing", "producer | grep -q needle # pipefail-grep-guard: allow\n", 0, true},
		{"unknown directive", "# pipefail-grep-guard: disable all\n", 0, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := scanSource("fixture.sh", []byte(tc.source))
			if (err != nil) != tc.bad {
				t.Fatalf("error=%v, want error=%v", err, tc.bad)
			}
			if !tc.bad && len(got) != tc.count {
				t.Fatalf("want %d findings, got %+v", tc.count, got)
			}
		})
	}
}

// TestInvalidShell prevents malformed input from being reported as a clean scan.
func TestInvalidShell(t *testing.T) {
	if _, err := scanSource("bad.sh", []byte("if then\n")); err == nil {
		t.Fatal("invalid shell accepted")
	}
}

// TestEarlyExitPipeline pins the actionable flag and its source location.
func TestEarlyExitPipeline(t *testing.T) {
	findings, err := scanSource("check.sh", []byte("set -o pipefail\nproducer | grep -q NEEDLE\n"))
	if err != nil {
		t.Fatal(err)
	}
	if len(findings) != 1 || findings[0].line != 2 || findings[0].flag != "-q" {
		t.Fatalf("expected one quiet-grep finding on line 2, got %+v", findings)
	}
}
