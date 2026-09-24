package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"sort"
	"strings"
)

const maxScriptBytes = 16 << 20

func run(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("validate-shell-pipelines", flag.ContinueOnError)
	flags.SetOutput(stderr)
	rootPath := flags.String("root", ".", "repository directory")
	paths := flags.String("paths", ".", "newline-separated relative files or directories")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 0 {
		fmt.Fprintln(stderr, "unexpected positional arguments")
		return 2
	}
	scopes, err := parseScopes(*paths)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	root, err := os.OpenRoot(*rootPath)
	if err != nil {
		fmt.Fprintln(stderr, "cannot open repository directory")
		return 2
	}
	defer root.Close()
	sources, err := discover(root, *rootPath, scopes)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	names := make([]string, 0, len(sources))
	for name := range sources {
		names = append(names, name)
	}
	sort.Strings(names)
	count := 0
	for _, name := range names {
		findings, err := scanSource(name, sources[name])
		if err != nil {
			fmt.Fprintf(stderr, "%q: %v\n", name, err)
			return 2
		}
		for _, f := range findings {
			fmt.Fprintf(stderr, "%q:%d: grep %s can stop a pipe early; capture the producer output and check its exit status before searching it\n", name, f.line, f.flag)
			count++
		}
	}
	if count > 0 {
		fmt.Fprintf(stderr, "Found %d unsafe pipeline(s) in %d shell file(s).\n", count, len(names))
		return 1
	}
	fmt.Fprintf(stdout, "Shell pipeline validation passed: %d shell file(s).\n", len(names))
	return 0
}

func parseScopes(input string) ([]string, error) {
	var scopes []string
	for _, line := range strings.Split(input, "\n") {
		scope := strings.TrimSpace(line)
		if scope == "" {
			continue
		}
		if strings.ContainsAny(scope, "\x00\\") || path.IsAbs(scope) || path.Clean(scope) != scope || scope == ".." || strings.HasPrefix(scope, "../") {
			return nil, fmt.Errorf("invalid scope %q: use clean relative file or directory paths", scope)
		}
		scopes = append(scopes, scope)
	}
	if len(scopes) == 0 {
		return nil, fmt.Errorf("at least one scope is required")
	}
	return scopes, nil
}

func discover(root *os.Root, rootPath string, scopes []string) (map[string][]byte, error) {
	sources := map[string][]byte{}
	for _, scope := range scopes {
		cmd := exec.Command("git", "--no-optional-locks", "--literal-pathspecs", "-C", rootPath, "-c", "core.fsmonitor=false", "ls-files", "--cached", "--stage", "-z", "--", scope)
		// A caller's alternate index/worktree must not silently change the scan set.
		for _, entry := range os.Environ() {
			if !strings.HasPrefix(entry, "GIT_") {
				cmd.Env = append(cmd.Env, entry)
			}
		}
		output, err := cmd.Output()
		if err != nil {
			return nil, fmt.Errorf("Git discovery failed for scope %q", scope)
		}
		matches := 0
		for _, record := range bytes.Split(output, []byte{0}) {
			if len(record) == 0 {
				continue
			}
			header, name, ok := strings.Cut(string(record), "\t")
			fields := strings.Fields(header)
			if !ok || len(fields) != 3 || fields[2] != "0" {
				return nil, fmt.Errorf("Git discovery returned an invalid or unmerged entry")
			}
			if fields[0] == "160000" {
				continue
			} // Submodules belong to their own checkouts.
			if _, err := parseScopes(name); err != nil {
				return nil, fmt.Errorf("Git discovery returned an invalid path")
			}
			if _, ok := sources[name]; ok {
				matches++
				continue
			}
			source, shell, err := readScript(root, name)
			if err != nil {
				return nil, fmt.Errorf("%q: %w", name, err)
			}
			if shell {
				sources[name] = source
				matches++
			}
		}
		if matches == 0 {
			return nil, fmt.Errorf("scope %q has no tracked shell files", scope)
		}
	}
	return sources, nil
}

func readScript(root *os.Root, name string) ([]byte, bool, error) {
	// Reject symlink components explicitly; OpenRoot also confines reads if a
	// checkout changes between inspection and opening the file.
	current := ""
	for _, part := range strings.Split(name, "/") {
		current = path.Join(current, part)
		info, err := root.Lstat(current)
		if err != nil {
			return nil, false, fmt.Errorf("cannot inspect tracked path")
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return nil, false, fmt.Errorf("symlink paths are not supported")
		}
		if current == name && !info.Mode().IsRegular() {
			return nil, false, fmt.Errorf("tracked path is not a regular file")
		}
	}
	file, err := root.Open(name)
	if err != nil {
		return nil, false, fmt.Errorf("cannot read tracked file")
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		return nil, false, fmt.Errorf("tracked path is not a regular file")
	}
	prefix, err := io.ReadAll(io.LimitReader(file, 4096))
	if err != nil {
		return nil, false, fmt.Errorf("cannot read tracked file")
	}
	shell := strings.HasSuffix(name, ".sh") || strings.HasSuffix(name, ".bash") || shellShebang(prefix)
	if !shell {
		return nil, false, nil
	}
	if info.Size() > maxScriptBytes {
		return nil, false, fmt.Errorf("shell file exceeds 16 MiB scan limit")
	}
	rest, err := io.ReadAll(io.LimitReader(file, maxScriptBytes+1-int64(len(prefix))))
	if err != nil || len(prefix)+len(rest) > maxScriptBytes {
		return nil, false, fmt.Errorf("cannot read shell file within scan limit")
	}
	return append(prefix, rest...), true, nil
}

func shellShebang(source []byte) bool {
	line, _, _ := bytes.Cut(source, []byte{'\n'})
	if !bytes.HasPrefix(line, []byte("#!")) {
		return false
	}
	fields := strings.Fields(string(line[2:]))
	if len(fields) == 0 {
		return false
	}
	if path.Base(fields[0]) == "env" {
		fields = fields[1:]
		if len(fields) > 0 && fields[0] == "-S" {
			fields = fields[1:]
		}
	}
	return len(fields) > 0 && (path.Base(fields[0]) == "bash" || path.Base(fields[0]) == "sh")
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }
