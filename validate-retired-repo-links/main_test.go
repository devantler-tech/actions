package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestConsumerLinks(t *testing.T) {
	const basic = `{"version":1,"repositories":["example/retired"],"paths":["docs"]}`
	cases := []struct {
		name, config, content string
		want                  int
		message               string
	}{
		{"retired link blocks", basic, "See https://github.com/example/retired/blob/main/README.md", 1, "docs/guide.md:1"},
		{"active link passes", basic, "See https://github.com/example/current", 0, "checked 1 text file"},
		{"repository suffix is distinct", basic, "https://github.com/example/retired-tools", 0, "checked 1 text file"},
		{"encoded suffix is outside scope", basic, "https://github.com/example/retired%2Dtools", 0, "checked 1 text file"},
		{"encoded slash is outside scope", basic, "https://github.com/example/retired%2Fother", 0, "checked 1 text file"},
		{"raw encoded suffix is outside scope", basic, "https://raw.githubusercontent.com/example/retired%2Dtools/main/file", 0, "checked 1 text file"},
		{"encoded clone suffix is outside scope", basic, "https://github.com/example/retired.git%2Dtools", 0, "checked 1 text file"},
		{"unsupported unicode suffix is outside scope", basic, "https://github.com/example/retiredø", 0, "checked 1 text file"},
		{"unsupported plus suffix is outside scope", basic, "https://github.com/example/retired+tools", 0, "checked 1 text file"},
		{"unsupported at suffix is outside scope", basic, "https://github.com/example/retired@tools", 0, "checked 1 text file"},
		{"markdown link still blocks", basic, "[old](https://github.com/example/retired)", 1, "example/retired"},
		{"bold link blocks", basic, "**https://github.com/example/retired**", 1, "example/retired"},
		{"italic link blocks", basic, "*https://github.com/example/retired*", 1, "example/retired"},
		{"nested emphasis blocks", basic, "***https://github.com/example/retired***", 1, "example/retired"},
		{"emphasized clone link blocks", basic, "**https://github.com/example/retired.git**", 1, "example/retired"},
		{"emphasized raw repository blocks", basic, "**https://raw.githubusercontent.com/example/retired**", 1, "example/retired"},
		{"emphasized distinct repository passes", basic, "**https://github.com/example/retired-tools**", 0, "checked 1 text file"},
		{"emphasized encoded name stays outside scope", basic, "**https://github.com/example/retired%2Dtools**", 0, "checked 1 text file"},
		{"underscore suffix stays literal", basic, "https://github.com/example/retired_", 0, "checked 1 text file"},
		{"underscore italic link blocks", basic, "_https://github.com/example/retired_", 1, "example/retired"},
		{"underscore bold link blocks", basic, "__https://github.com/example/retired__", 1, "example/retired"},
		{"underscore nested link blocks", basic, "___https://github.com/example/retired___", 1, "example/retired"},
		{"underscore clone link blocks", basic, "_https://github.com/example/retired.git_", 1, "example/retired"},
		{"underscore sentence link blocks", basic, "_https://github.com/example/retired_.", 1, "example/retired"},
		{"struck link blocks", basic, "~~https://github.com/example/retired~~", 1, "example/retired"},
		{"struck raw link blocks", basic, "~~https://raw.githubusercontent.com/example/retired~~", 1, "example/retired"},
		{"single struck link blocks", basic, "~https://github.com/example/retired~", 1, "example/retired"},
		{"mixed emphasis link blocks", basic, "**_https://github.com/example/retired_**", 1, "example/retired"},
		{"mixed strike emphasis link blocks", basic, "*~~https://github.com/example/retired~~*", 1, "example/retired"},
		{"three tilde suffix stays outside scope", basic, "~~~https://github.com/example/retired~~~", 0, "checked 1 text file"},
		{"formatted distinct underscore name passes", basic, "_https://github.com/example/retired_tools_", 0, "checked 1 text file"},
		{"underscore repository with path stays literal", basic, "_https://github.com/example/retired_/main_", 0, "checked 1 text file"},
		{"underscore repository with query stays literal", basic, "_https://github.com/example/retired_?view=1_", 0, "checked 1 text file"},
		{"unpaired tilde suffix stays outside scope", basic, "https://github.com/example/retired~tools", 0, "checked 1 text file"},
		{"struck distinct repository passes", basic, "~~https://github.com/example/retired-tools~~", 0, "checked 1 text file"},
		{"unbalanced tilde stays outside scope", basic, "~~https://github.com/example/retired~tools~~", 0, "checked 1 text file"},
		{"embedded scheme passes", basic, "nothttps://github.com/example/retired", 0, "checked 1 text file"},
		{"embedded HTTP scheme passes", basic, "nothttp://github.com/example/retired", 0, "checked 1 text file"},
		{"unicode token prefix passes", basic, "øhttps://github.com/example/retired", 0, "checked 1 text file"},
		{"URL path token passes", basic, "https://example.com/https://github.com/example/retired", 0, "checked 1 text file"},
		{"underscore token prefix passes", basic, "prefix_https://github.com/example/retired", 0, "checked 1 text file"},
		{"assignment URL blocks", basic, "url=https://github.com/example/retired", 1, "example/retired"},
		{"unicode whitespace URL blocks", basic, "See\u00a0https://github.com/example/retired", 1, "example/retired"},
		{"HTML text URL blocks", basic, "<p>https://github.com/example/retired</p>", 1, "example/retired"},
		{"autolink still blocks", basic, "<https://github.com/example/retired>", 1, "example/retired"},
		{"fragment still blocks", basic, "https://github.com/example/retired#readme", 1, "example/retired"},
		{"inline code still blocks", basic, "`https://github.com/example/retired`", 1, "example/retired"},
		{"space followed by prose still blocks", basic, "https://github.com/example/retired is retired", 1, "example/retired"},
		{"different owner passes", basic, "https://github.com/other/retired", 0, "checked 1 text file"},
		{"mixed case blocks", basic, "HTTPS://GitHub.com/EXAMPLE/RETIRED", 1, "example/retired"},
		{"raw content blocks", basic, "https://raw.githubusercontent.com/example/retired/main/file", 1, "example/retired"},
		{"clone link blocks", basic, "https://github.com/example/retired.git", 1, "example/retired"},
		{"sentence punctuation blocks", basic, "See https://github.com/example/retired.", 1, "example/retired"},
		{"colon punctuation blocks", basic, "See https://github.com/example/retired: moved", 1, "example/retired"},
		{"colon after a distinct name passes", basic, "See https://github.com/example/retired-tools: moved", 0, "checked 1 text file"},
		{"line number is useful", basic, "current\nhttps://github.com/example/retired/issues/1\n", 1, "docs/guide.md:2"},
		{"plain historical prose passes", basic, "Merged example/retired into example/current", 0, "checked 1 text file"},
		{"documented exception passes", `{"version":1,"repositories":["example/retired"],"paths":["docs"],"exceptions":[{"path":"docs/guide.md","repository":"example/retired","reason":"Historical migration record"}]}`, "https://github.com/example/retired", 0, "allowed 1"},
		{"exception cannot hide another file", `{"version":1,"repositories":["example/retired"],"paths":["docs"],"exceptions":[{"path":"docs/history.md","repository":"example/retired","reason":"History"}]}`, "https://github.com/example/retired", 1, "docs/guide.md:1"},
		{"exception cannot hide another repository", `{"version":1,"repositories":["example/retired","example/other"],"paths":["docs"],"exceptions":[{"path":"docs/guide.md","repository":"example/other","reason":"History"}]}`, "https://github.com/example/retired", 1, "example/retired"},
		{"missing reason blocks", `{"version":1,"repositories":["example/retired"],"paths":["docs"],"exceptions":[{"path":"docs/guide.md","repository":"example/retired"}]}`, "safe", 2, "reason"},
		{"unknown keys block", `{"version":1,"repositories":["example/retired"],"paths":["docs"],"typo":true}`, "safe", 2, "configuration"},
		{"trailing JSON blocks", basic + `{}`, "safe", 2, "configuration"},
		{"empty repositories block", `{"version":1,"repositories":[],"paths":["docs"]}`, "safe", 2, "repositories"},
		{"empty paths block", `{"version":1,"repositories":["example/retired"],"paths":[]}`, "safe", 2, "paths"},
		{"unsupported version blocks", `{"version":2,"repositories":["example/retired"],"paths":["docs"]}`, "safe", 2, "version"},
		{"URL is not repository name", `{"version":1,"repositories":["https://github.com/example/retired"],"paths":["docs"]}`, "safe", 2, "owner/repository"},
		{"missing target blocks", `{"version":1,"repositories":["example/retired"],"paths":["missing"]}`, "safe", 2, "missing"},
		{"escape blocks", `{"version":1,"repositories":["example/retired"],"paths":["../outside"]}`, "safe", 2, "relative"},
		{"absolute path blocks", `{"version":1,"repositories":["example/retired"],"paths":["/tmp"]}`, "safe", 2, "relative"},
		{"non-text-only scope blocks", basic, "binary\x00data", 2, "no text files"},
		{"content not leaked", basic, "TOP_SECRET https://github.com/example/retired?token=PRIVATE", 1, "docs/guide.md:1"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root := t.TempDir()
			writeFixture(t, root, ".github/retired-repo-links.json", tc.config)
			writeFixture(t, root, "docs/guide.md", tc.content)
			var output bytes.Buffer
			got := run([]string{"--root", root}, &output)
			if got != tc.want || !strings.Contains(output.String(), tc.message) {
				t.Fatalf("exit=%d output=%q; want exit=%d containing %q", got, output.String(), tc.want, tc.message)
			}
			if strings.Contains(output.String(), "TOP_SECRET") || strings.Contains(output.String(), "PRIVATE") {
				t.Fatal("diagnostic leaked document content")
			}
			data, err := os.ReadFile(filepath.Join(root, "docs/guide.md"))
			if err != nil || string(data) != tc.content {
				t.Fatal("validator changed consumer content")
			}
		})
	}
}

func TestFilesystemBoundaries(t *testing.T) {
	for _, directory := range []bool{false, true} {
		t.Run(map[bool]string{false: "file", true: "directory"}[directory], func(t *testing.T) {
			root, outside := t.TempDir(), t.TempDir()
			writeFixture(t, root, ".github/retired-repo-links.json", `{"version":1,"repositories":["example/retired"],"paths":["docs"]}`)
			writeFixture(t, outside, "secret.md", "private data")
			target := filepath.Join(outside, "secret.md")
			if directory {
				target = outside
			}
			if err := os.Symlink(target, filepath.Join(root, "docs")); err != nil {
				t.Fatal(err)
			}
			var output bytes.Buffer
			if code := run([]string{"--root", root}, &output); code != 2 || !strings.Contains(output.String(), "symlink") {
				t.Fatalf("exit=%d output=%q", code, output.String())
			}
		})
	}
}

func TestOverlappingPathsDoNotDuplicateFindings(t *testing.T) {
	root := t.TempDir()
	writeFixture(t, root, ".github/retired-repo-links.json", `{"version":1,"repositories":["example/retired"],"paths":["docs","docs/guide.md"]}`)
	writeFixture(t, root, "docs/guide.md", "https://github.com/example/retired")
	var output bytes.Buffer
	if code := run([]string{"--root", root}, &output); code != 1 || strings.Count(output.String(), "docs/guide.md:1") != 1 {
		t.Fatalf("exit=%d output=%q", code, output.String())
	}
}

func TestMissingConfigAndInvalidArguments(t *testing.T) {
	for _, args := range [][]string{{"--root", t.TempDir()}, {"--unknown"}, {"unexpected"}} {
		var output bytes.Buffer
		if code := run(args, &output); code != 2 {
			t.Fatalf("args=%v exit=%d", args, code)
		}
	}
}

func writeFixture(t *testing.T, root, name, content string) {
	t.Helper()
	file := filepath.Join(root, name)
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
}
