package main

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"

	"go.yaml.in/yaml/v3"
)

type config struct {
	Version                   int      `yaml:"version"`
	ResourceRoots             []string `yaml:"resource-roots"`
	PatchRoots                []string `yaml:"patch-roots"`
	CRDirectories             []string `yaml:"cr-directories"`
	MultiResourceFiles        []string `yaml:"multi-resource-files"`
	KindPrefixExemptFiles     []string `yaml:"kind-prefix-exempt-files"`
	FilenameExemptDirectories []string `yaml:"filename-exempt-directories"`
}

// loadConfig accepts exactly one versioned document and rejects unknown fields.
func loadConfig(file string) (config, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return config{}, fmt.Errorf("open configuration: %w", err)
	}
	var cfg config
	d := yaml.NewDecoder(bytes.NewReader(data))
	d.KnownFields(true)
	if err := d.Decode(&cfg); err != nil {
		return cfg, errors.New("configuration must be valid YAML with only documented fields")
	}
	var extra yaml.Node
	if err := d.Decode(&extra); !errors.Is(err, io.EOF) {
		return cfg, errors.New("configuration must contain exactly one YAML document")
	}
	return cfg, cfg.check()
}

// check validates repository-relative paths, pattern syntax, and root separation.
func (c config) check() error {
	if c.Version != 1 {
		return errors.New("configuration version must be 1")
	}
	if len(c.ResourceRoots)+len(c.PatchRoots) == 0 {
		return errors.New("configure at least one resource-roots or patch-roots directory")
	}
	for _, field := range []struct {
		name     string
		values   []string
		patterns bool
	}{
		{"resource-roots", c.ResourceRoots, true}, {"patch-roots", c.PatchRoots, true},
		{"cr-directories", c.CRDirectories, false}, {"multi-resource-files", c.MultiResourceFiles, false},
		{"kind-prefix-exempt-files", c.KindPrefixExemptFiles, true}, {"filename-exempt-directories", c.FilenameExemptDirectories, false},
	} {
		for _, value := range field.values {
			if value == "." || path.IsAbs(value) || path.Clean(value) != value || strings.HasPrefix(value, "../") || value == ".." || strings.ContainsAny(value, "\\\r\n\x00") {
				return fmt.Errorf("%s entries must be normalized repository-relative paths", field.name)
			}
			if field.patterns {
				if _, err := path.Match(value, ""); err != nil {
					return fmt.Errorf("%s contains an invalid path pattern", field.name)
				}
			} else if strings.ContainsAny(value, "*?[]") {
				return fmt.Errorf("%s does not support glob patterns", field.name)
			}
		}
	}
	roots := append(append([]string{}, c.ResourceRoots...), c.PatchRoots...)
	for i, root := range roots {
		for j, other := range roots {
			if i != j && under(root, []string{other}) {
				return errors.New("scan roots must not overlap")
			}
		}
	}
	return nil
}

// expandRoots selects real directories and rejects unmatched or overlapping patterns.
func (c config) expandRoots(root string) (config, error) {
	for _, roots := range []*[]string{&c.ResourceRoots, &c.PatchRoots} {
		var expanded []string
		for _, pattern := range *roots {
			matches, err := fs.Glob(os.DirFS(root), pattern)
			if err != nil {
				return c, fmt.Errorf("scan root %q: invalid pattern", pattern)
			}
			var directories []string
			for _, match := range matches {
				info, err := os.Lstat(filepath.Join(root, filepath.FromSlash(match)))
				if err != nil {
					return c, fmt.Errorf("scan root %q: %w", pattern, err)
				}
				if info.Mode()&os.ModeSymlink != 0 {
					return c, fmt.Errorf("scan root %q: symlinks are not supported", match)
				}
				if info.IsDir() {
					directories = append(directories, match)
				}
			}
			if len(directories) == 0 {
				return c, fmt.Errorf("scan root %q did not match a directory", pattern)
			}
			expanded = append(expanded, directories...)
		}
		*roots = expanded
	}
	return c, c.check() // Also reject overlaps that appear only after pattern expansion.
}
