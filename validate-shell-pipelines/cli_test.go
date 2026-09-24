package main

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// git prepares a fixture index and attributes setup failures to the calling test.
func git(t *testing.T, root string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git: %v: %s", err, out)
	}
}

// fixture creates tracked inputs without requiring commits or signing credentials.
func fixture(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	git(t, root, "init", "--quiet")
	for name, source := range files {
		file := filepath.Join(root, name)
		if err := os.MkdirAll(filepath.Dir(file), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(file, []byte(source), 0644); err != nil {
			t.Fatal(err)
		}
		git(t, root, "add", "--", name)
	}
	return root
}

// checkRun checks the CLI contract while retaining both streams for privacy assertions.
func checkRun(t *testing.T, args []string, status int, contains string) string {
	t.Helper()
	var out, errors bytes.Buffer
	got := run(args, &out, &errors)
	all := out.String() + errors.String()
	if got != status || !strings.Contains(all, contains) {
		t.Fatalf("status=%d want=%d, output=%q must contain %q", got, status, all, contains)
	}
	return all
}

// TestTrackedScope proves scoping, deduplication, and source-free file diagnostics.
func TestTrackedScope(t *testing.T) {
	root := fixture(t, map[string]string{
		"scripts/check space ø.sh": "#!/bin/bash\nproducer | grep -q SECRET_PATTERN\n",
		"scripts/helper":           "#!/usr/bin/env bash\nproducer | grep --quiet value\n",
		"other/safe.bash":          "printf 'safe'\n",
		"README.md":                "producer | grep -q not-code\n",
	})
	if err := os.WriteFile(filepath.Join(root, "untracked.sh"), []byte("if then\n"), 0644); err != nil {
		t.Fatal(err)
	}
	out := checkRun(t, []string{"--root", root, "--paths", "scripts"}, 1, "check space ø.sh\":2")
	if strings.Contains(out, "SECRET_PATTERN") {
		t.Fatal("diagnostic leaked source text")
	}
	if !strings.Contains(out, "helper\":2") {
		t.Fatal("extensionless shell was not scanned")
	}
	checkRun(t, []string{"--root", root, "--paths", "other"}, 0, "1 shell file")
	checkRun(t, []string{"--root", root, "--paths", "other\nother/safe.bash"}, 0, "1 shell file")
	checkRun(t, []string{"--root", filepath.Join(root, "other")}, 0, "1 shell file")
}

// TestInvalidScans requires incomplete scans to fail without disclosing source text.
func TestInvalidScans(t *testing.T) {
	for _, scope := range []string{"", "missing", "../escape", "/tmp", ":(glob)*", "*.sh", "safe.sh\nmissing", "README.md", "./safe.sh"} {
		t.Run(scope, func(t *testing.T) {
			root := fixture(t, map[string]string{"safe.sh": "true\n", "README.md": "text\n"})
			checkRun(t, []string{"--root", root, "--paths", scope}, 2, "")
		})
	}
	t.Run("not git", func(t *testing.T) { checkRun(t, []string{"--root", t.TempDir()}, 2, "Git discovery failed") })
	t.Run("missing root", func(t *testing.T) { checkRun(t, []string{"--root", filepath.Join(t.TempDir(), "missing")}, 2, "") })
	t.Run("invalid syntax", func(t *testing.T) {
		root := fixture(t, map[string]string{"bad.sh": "true\n  if then SECRET\n"})
		out := checkRun(t, []string{"--root", root}, 2, "line 2 column 3: invalid shell syntax (source omitted)")
		if strings.Contains(out, "SECRET") {
			t.Fatal("parser leaked source")
		}
	})
	t.Run("unsupported language syntax", func(t *testing.T) {
		root := fixture(t, map[string]string{"bad.sh": "true\necho ${SECRET@#}\n"})
		out := checkRun(t, []string{"--root", root}, 2, "line 2 column 15: invalid shell syntax (source omitted)")
		if strings.Contains(out, "SECRET") {
			t.Fatal("language parser leaked source")
		}
	})
	t.Run("tracked deletion", func(t *testing.T) {
		root := fixture(t, map[string]string{"gone.sh": "true\n"})
		if err := os.Remove(filepath.Join(root, "gone.sh")); err != nil {
			t.Fatal(err)
		}
		checkRun(t, []string{"--root", root}, 2, "")
	})
	t.Run("symlink", func(t *testing.T) {
		root := fixture(t, map[string]string{"safe.sh": "true\n"})
		if err := os.Symlink("safe.sh", filepath.Join(root, "link.sh")); err != nil {
			t.Fatal(err)
		}
		git(t, root, "add", "link.sh")
		checkRun(t, []string{"--root", root}, 2, "symlink")
	})
	t.Run("symlink directory", func(t *testing.T) {
		root := fixture(t, map[string]string{"dir/safe.sh": "true\n"})
		if err := os.Rename(filepath.Join(root, "dir"), filepath.Join(root, "real")); err != nil {
			t.Fatal(err)
		}
		if err := os.Symlink("real", filepath.Join(root, "dir")); err != nil {
			t.Fatal(err)
		}
		checkRun(t, []string{"--root", root}, 2, "symlink")
	})
	t.Run("no shell", func(t *testing.T) {
		root := fixture(t, map[string]string{"README.md": "text"})
		checkRun(t, []string{"--root", root}, 2, "no tracked shell")
	})
	t.Run("argument", func(t *testing.T) { checkRun(t, []string{"--unknown"}, 2, ""); checkRun(t, []string{"extra"}, 2, "") })
}

// TestDoesNotExecute checks that discovering a dangerous command never runs it.
func TestDoesNotExecute(t *testing.T) {
	root := fixture(t, map[string]string{"unsafe.sh": "#!/bin/bash\ntouch EXECUTED\nproducer | grep -q value\n"})
	checkRun(t, []string{"--root", root}, 1, "capture")
	if _, err := os.Stat(filepath.Join(root, "EXECUTED")); !os.IsNotExist(err) {
		t.Fatal("scanned script was executed")
	}
}

// TestRealSIGPIPEAndSafeCapture signals after grep matched. The producer then writes more
// than a pipe can buffer, forcing SIGPIPE instead of depending on scheduling.
func TestRealSIGPIPEAndSafeCapture(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "bash", "-c", `set -uo pipefail
producer() {
  printf 'needle\n'
  while [[ ! -f matched ]]; do :; done
  printf '%1048576s' x
}
consumer() { grep -q needle; local result=$?; : > matched; return "$result"; }
producer | consumer
statuses=( "${PIPESTATUS[@]}" )
[[ ${statuses[0]} -eq 141 && ${statuses[1]} -eq 0 ]] || exit 10
rm matched
if ! producer | consumer; then
  printf 'unsafe negated assertion passed despite a match\n'
else
  exit 11
fi
safe_producer() { printf 'needle\n'; printf '%1048576s' x; }
captured=$(safe_producer) || exit 12
grep -q needle <<< "$captured" || exit 13
failing_producer() { printf 'needle\n'; return 42; }
result=0
captured=$(failing_producer) || result=$?
[[ $result -eq 42 ]] || exit 14
printf 'safe capture preserved producer failure\n'
`)
	cmd.Dir = t.TempDir()
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("real pipeline proof: %v: %s", err, out)
	}
	if !strings.Contains(string(out), "safe capture preserved producer failure") {
		t.Fatalf("missing acceptance: %s", out)
	}
}

// TestScanLimitsAndEnvironment checks filesystem bounds and hostile Git environment state.
func TestScanLimitsAndEnvironment(t *testing.T) {
	t.Run("filesystem monitor is not executed", func(t *testing.T) {
		root := fixture(t, map[string]string{"safe.sh": "true\n"})
		hook := filepath.Join(root, "monitor")
		if err := os.WriteFile(hook, []byte("#!/bin/sh\ntouch MONITOR_EXECUTED\n"), 0755); err != nil {
			t.Fatal(err)
		}
		git(t, root, "config", "core.fsmonitor", hook)
		checkRun(t, []string{"--root", root}, 0, "1 shell file")
		if _, err := os.Stat(filepath.Join(root, "MONITOR_EXECUTED")); !os.IsNotExist(err) {
			t.Fatal("Git executed a repository-controlled monitor")
		}
	})
	t.Run("unmerged index", func(t *testing.T) {
		root := fixture(t, map[string]string{"conflict.sh": "true\n"})
		out, err := exec.Command("git", "-C", root, "rev-parse", ":conflict.sh").Output()
		if err != nil {
			t.Fatal(err)
		}
		oid := strings.TrimSpace(string(out))
		git(t, root, "update-index", "--force-remove", "conflict.sh")
		cmd := exec.Command("git", "-C", root, "update-index", "--index-info")
		cmd.Stdin = strings.NewReader("100644 " + oid + " 1\tconflict.sh\n100644 " + oid + " 2\tconflict.sh\n")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("create conflict: %v: %s", err, out)
		}
		checkRun(t, []string{"--root", root}, 2, "unmerged")
	})
	t.Run("tracked file replaced with directory", func(t *testing.T) {
		root := fixture(t, map[string]string{"check.sh": "true\n"})
		name := filepath.Join(root, "check.sh")
		if err := os.Remove(name); err != nil {
			t.Fatal(err)
		}
		if err := os.Mkdir(name, 0755); err != nil {
			t.Fatal(err)
		}
		checkRun(t, []string{"--root", root}, 2, "not a regular file")
	})
	t.Run("oversized", func(t *testing.T) {
		root := fixture(t, map[string]string{"large.sh": "true\n"})
		if err := os.Truncate(filepath.Join(root, "large.sh"), maxScriptBytes+1); err != nil {
			t.Fatal(err)
		}
		checkRun(t, []string{"--root", root}, 2, "16 MiB")
	})
	t.Run("alternate index", func(t *testing.T) {
		root := fixture(t, map[string]string{"bad.sh": "producer | grep -q needle\n"})
		t.Setenv("GIT_INDEX_FILE", filepath.Join(t.TempDir(), "alternate-index"))
		checkRun(t, []string{"--root", root}, 1, "bad.sh")
	})
	t.Run("extensionless env split", func(t *testing.T) {
		root := fixture(t, map[string]string{"check": "#!/usr/bin/env -S bash -eu\nproducer | grep -q needle\n"})
		checkRun(t, []string{"--root", root}, 1, "check")
	})
}
