// Command validate-retired-repo-links checks consumer documentation without network access.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

func main() { os.Exit(run(os.Args[1:], os.Stdout)) }

type configuration struct {
	Version      int         `json:"version"`
	Repositories []string    `json:"repositories"`
	Paths        []string    `json:"paths"`
	Exceptions   []exception `json:"exceptions"`
}

type exception struct {
	Path       string `json:"path"`
	Repository string `json:"repository"`
	Reason     string `json:"reason"`
}

var repositoryName = regexp.MustCompile(`^[a-z0-9][a-z0-9-]*/[a-z0-9_.-]+$`)

// The pattern is matched against asciiLower(text), so case folding stays within
// ASCII: a Unicode letter that folds to one never extends a repository name.
var repositoryURL = regexp.MustCompile(`https?://(?:www\.)?(?:github\.com|raw\.githubusercontent\.com)/([a-z0-9-]+/[a-z0-9_.-]+)`)

// asciiLower lowercases only ASCII letters, so byte offsets are unchanged.
func asciiLower(text string) string {
	return strings.Map(func(r rune) rune {
		if 'A' <= r && r <= 'Z' {
			return r + 'a' - 'A'
		}
		return r
	}, text)
}

// Non-ASCII punctuation, such as typographic quotes, ends a URL in prose; GitHub
// names are ASCII, so it can never be part of one.
func typographicPunctuation(r rune) bool {
	return r >= utf8.RuneSelf && unicode.IsPunct(r)
}

// Check the end of the complete greedy match rather than adding a regex suffix:
// backtracking at a dot could otherwise turn a distinct name into a prefix match.
// Percent escapes and unsupported name characters are outside the literal scope.
func repositoryBoundary(text string, end int) bool {
	if end == len(text) {
		return true
	}
	next, _ := utf8.DecodeRuneInString(text[end:])
	return unicode.IsSpace(next) || strings.ContainsRune("/?#\"'`<>[](),:;!|}*", next) || typographicPunctuation(next)
}

// closingMarkup reports how many trailing characters of the captured name belong
// to the markup that closes opener. Paired markup closes in reverse order, so
// _~~url~~_ and ~~_url_~~ both pair; a repository name may itself end in
// underscores, so the closing run can begin inside the greedy capture.
func closingMarkup(text string, match []int, opener string) (int, bool) {
	// GFM strike delimiters contain one or two tildes.
	for _, run := range strings.FieldsFunc(opener, func(r rune) bool { return r != '~' }) {
		if len(run) > 2 {
			return 0, false
		}
	}
	closer := []byte(opener)
	for i, j := 0, len(closer)-1; i < j; i, j = i+1, j-1 {
		closer[i], closer[j] = closer[j], closer[i]
	}
	name := text[match[2]:match[3]]
	inside := len(closer) - len(bytes.TrimLeft(closer, "_"))
	if len(closer) > 0 && inside < len(name) && inside <= len(name)-len(strings.TrimRight(name, "_")) &&
		strings.HasPrefix(text[match[1]-inside:], string(closer)) && repositoryBoundary(text, match[1]-inside+len(closer)) {
		return inside, true
	}
	// Strikethrough may close inside unclosed emphasis: *~~url~~ still pairs its tildes.
	tildes := len(opener) - len(strings.TrimRight(opener, "~"))
	if tildes >= 1 && strings.HasPrefix(text[match[1]:], strings.Repeat("~", tildes)) && repositoryBoundary(text, match[1]+tildes) {
		return 0, true
	}
	return 0, false
}

// repositoryReference checks both ends of a literal URL. Formatting immediately
// around it may be paired Markdown punctuation, but never a repository suffix
// inferred from the retired-name list. This is not a general Markdown renderer.
func repositoryReference(text string, match []int) (string, bool) {
	start := match[0]
	for start > 0 && strings.ContainsRune("*_~", rune(text[start-1])) {
		start--
	}
	if start > 0 {
		previous, _ := utf8.DecodeLastRuneInString(text[:start])
		if !unicode.IsSpace(previous) && !strings.ContainsRune("\"'`<>[](){}=,:;!?|", previous) && !typographicPunctuation(previous) {
			return "", false
		}
	}
	opener := text[start:match[0]]
	if !repositoryBoundary(text, match[1]) {
		inside, closed := closingMarkup(text, match, opener)
		if !closed {
			return "", false
		}
		return strings.TrimRight(asciiLower(text[match[2]:match[3]-inside]), "."), true
	}
	repo := strings.TrimRight(asciiLower(text[match[2]:match[3]]), ".")
	underscores := len(opener) - len(strings.TrimRight(opener, "_"))
	closing := len(repo) - len(strings.TrimRight(repo, "_"))
	// A slash/query/fragment means the URL continues: in _.../repo_/path_,
	// the first underscore belongs to the repository, not the closing markup.
	if underscores > 0 && closing == underscores &&
		(match[1] == len(text) || !strings.ContainsRune("/?#", rune(text[match[1]]))) {
		repo = repo[:len(repo)-closing]
	}
	return strings.TrimRight(repo, "."), true
}

func run(args []string, output io.Writer) int {
	flags := flag.NewFlagSet("validate-retired-repo-links", flag.ContinueOnError)
	flags.SetOutput(output)
	rootPath := flags.String("root", ".", "consumer repository directory")
	configPath := flags.String("config", ".github/retired-repo-links.json", "configuration relative to root")
	if err := flags.Parse(args); err != nil || flags.NArg() != 0 {
		return 2
	}
	root, err := os.OpenRoot(*rootPath)
	if err != nil {
		fmt.Fprintln(output, "Cannot open consumer root:", err)
		return 2
	}
	defer root.Close()
	config, err := loadConfig(root, *configPath)
	if err != nil {
		fmt.Fprintln(output, "Invalid configuration:", err)
		return 2
	}
	violations, err := scan(root, config, output)
	if err != nil {
		fmt.Fprintln(output, "Scan incomplete:", err)
		return 2
	}
	if violations > 0 {
		fmt.Fprintln(output, "Replace retired-repository URLs, or document intentional history with an exact path/repository exception.")
		return 1
	}
	return 0
}

// Colons and backslashes are ordinary filename characters on the supported Linux
// and macOS runners; os.Root confines every read to the consumer root either way.
func localPath(name string) bool {
	return fs.ValidPath(name) && (runtime.GOOS != "windows" || !strings.ContainsAny(name, "\\:"))
}

// Root confines reads even if a checked-out path changes during validation.
// Reject symlinks inside the root as well, so scan scope is explicit.
func checkPath(root *os.Root, name string) error {
	if !localPath(name) {
		return fmt.Errorf("%q must be a clean relative path", name)
	}
	current := "."
	for _, part := range strings.Split(name, "/") {
		current = path.Join(current, part)
		info, err := root.Lstat(current)
		if err != nil {
			return fmt.Errorf("cannot inspect %q: %w", current, err)
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("symlink is outside supported scan scope: %q", current)
		}
	}
	return nil
}

func readFile(root *os.Root, name string) ([]byte, error) {
	if err := checkPath(root, name); err != nil {
		return nil, err
	}
	info, err := root.Lstat(name)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("%q is not a regular file", name)
	}
	file, err := root.Open(name)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err = file.Stat()
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() {
		return nil, fmt.Errorf("%q is not a regular file", name)
	}
	const maxFileSize = 16 * 1024 * 1024
	data, err := io.ReadAll(io.LimitReader(file, maxFileSize+1))
	if err == nil && len(data) > maxFileSize {
		err = fmt.Errorf("%q exceeds the 16 MiB scan limit", name)
	}
	return data, err
}

func loadConfig(root *os.Root, name string) (configuration, error) {
	var config configuration
	data, err := readFile(root, name)
	if err != nil {
		return config, err
	}
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&config); err != nil {
		// Decoder errors may include document values; do not print them.
		return config, errors.New("configuration must use the documented JSON schema")
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		return config, errors.New("configuration must contain exactly one JSON document")
	}
	if config.Version != 1 {
		return config, errors.New("version must be 1")
	}
	if len(config.Repositories) == 0 || len(config.Paths) == 0 {
		return config, errors.New("repositories and paths must both be nonempty")
	}
	repositories := make(map[string]bool)
	for i, repo := range config.Repositories {
		repo = asciiLower(repo)
		if !repositoryName.MatchString(repo) || path.Base(repo) == "." || path.Base(repo) == ".." || repositories[repo] {
			return config, errors.New("repositories must be unique owner/repository names")
		}
		config.Repositories[i], repositories[repo] = repo, true
	}
	for _, name := range config.Paths {
		if !localPath(name) {
			return config, fmt.Errorf("%q must be a clean relative path", name)
		}
	}
	for i, item := range config.Exceptions {
		if !localPath(item.Path) || item.Path == "." || strings.TrimSpace(item.Reason) == "" {
			return config, errors.New("each exception needs an exact relative file path and a nonempty reason")
		}
		item.Repository = asciiLower(item.Repository)
		if !repositories[item.Repository] {
			return config, errors.New("exception repository must be present in repositories")
		}
		config.Exceptions[i] = item
	}
	return config, nil
}

func scan(root *os.Root, config configuration, output io.Writer) (int, error) {
	repositories, exceptions := make(map[string]bool), make(map[string]bool)
	for _, repo := range config.Repositories {
		repositories[repo] = true
	}
	for _, item := range config.Exceptions {
		exceptions[item.Path+"\x00"+item.Repository] = true
	}
	seen := make(map[string]bool)
	checked, allowed, violations, binary := 0, 0, 0, 0
	for _, start := range config.Paths {
		if err := checkPath(root, start); err != nil {
			return violations, err
		}
		err := fs.WalkDir(root.FS(), start, func(name string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if entry.Type()&os.ModeSymlink != 0 {
				return fmt.Errorf("symlink is outside supported scan scope: %q", name)
			}
			if entry.IsDir() || seen[name] {
				return nil
			}
			seen[name] = true
			data, err := readFile(root, name)
			if err != nil {
				return err
			}
			if bytes.ContainsRune(data, 0) || !utf8.Valid(data) {
				binary++
				return nil
			}
			checked++
			for line, text := range strings.Split(string(data), "\n") {
				for _, match := range repositoryURL.FindAllStringSubmatchIndex(asciiLower(text), -1) {
					repo, literal := repositoryReference(text, match)
					if !literal {
						continue
					}
					if !repositories[repo] {
						repo = strings.TrimSuffix(repo, ".git")
					}
					if !repositories[repo] {
						continue
					}
					if exceptions[name+"\x00"+repo] {
						allowed++
						continue
					}
					// Quote control characters in paths and omit document contents.
					safePath := strings.Trim(strconv.Quote(name), "\"")
					fmt.Fprintf(output, "%s:%d: link targets retired repository %s\n", safePath, line+1, repo)
					violations++
				}
			}
			return nil
		})
		if err != nil {
			return violations, err
		}
	}
	if checked == 0 {
		return violations, errors.New("scan scope contains no text files")
	}
	fmt.Fprintf(output, "checked %d text file(s); allowed %d historical link(s); found %d retired link(s); skipped %d binary file(s)\n", checked, allowed, violations, binary)
	return violations, nil
}
