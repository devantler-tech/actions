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
	"regexp"
	"slices"
	"strings"

	"go.yaml.in/yaml/v3"
)

type violation struct{ Path, Rule, Message string }

type document struct{ api, kind string }

var kebabName = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
var acronymBoundary = regexp.MustCompile(`([A-Z]+)([A-Z][a-z])`)
var wordBoundary = regexp.MustCompile(`([a-z0-9])([A-Z])`)

func kebab(kind string) string {
	return strings.ToLower(wordBoundary.ReplaceAllString(acronymBoundary.ReplaceAllString(kind, "${1}-${2}"), "${1}-${2}"))
}

func plural(kind string) string {
	word := kebab(kind)
	for _, suffix := range []string{"s", "x", "z", "ch", "sh"} {
		if strings.HasSuffix(word, suffix) {
			return word + "es"
		}
	}
	if strings.HasSuffix(word, "y") && (len(word) < 2 || !strings.ContainsRune("aeiou", rune(word[len(word)-2]))) {
		return strings.TrimSuffix(word, "y") + "ies"
	}
	return word + "s"
}

func under(name string, dirs []string) bool {
	return slices.ContainsFunc(dirs, func(dir string) bool { return name == dir || strings.HasPrefix(name, dir+"/") })
}

func matches(name string, patterns []string) bool {
	return slices.ContainsFunc(patterns, func(pattern string) bool {
		ok, err := path.Match(pattern, name)
		return err == nil && ok // Configuration validation rejects malformed patterns.
	})
}

func leadsWith(stem, prefix string) bool {
	return stem == prefix || strings.HasPrefix(stem, prefix+"-")
}

func documents(file string) ([]document, error) {
	data, err := os.ReadFile(file)
	if err != nil {
		return nil, fmt.Errorf("open manifest: %w", err)
	}
	decoder := yaml.NewDecoder(bytes.NewReader(data))
	var docs []document
	for index := 1; ; index++ {
		var node yaml.Node
		if err := decoder.Decode(&node); errors.Is(err, io.EOF) {
			break
		} else if err != nil {
			return nil, fmt.Errorf("invalid YAML in document %d", index)
		}
		if len(node.Content) == 0 {
			continue
		}
		value := node.Content[0]
		if value.Tag == "!!null" && value.Value == "" {
			continue
		} // Empty/comment-only document.
		var decoded any
		if err := node.Decode(&decoded); err != nil {
			return nil, fmt.Errorf("invalid YAML mapping in document %d", index)
		}
		doc := document{}
		fields, stringKeys := decoded.(map[string]any)
		if value.Kind == yaml.MappingNode && !stringKeys {
			return nil, fmt.Errorf("document %d: mapping keys must be strings", index)
		}
		if stringKeys {
			for key, destination := range map[string]*string{"apiVersion": &doc.api, "kind": &doc.kind} {
				if raw, exists := fields[key]; exists {
					text, ok := raw.(string)
					if !ok || strings.TrimSpace(text) == "" {
						return nil, fmt.Errorf("document %d: %s must be a nonempty string", index, key)
					}
					*destination = text
				}
			}
		}
		docs = append(docs, doc)
	}
	return docs, nil
}

type scan struct {
	cfg        config
	violations []violation
	folders    map[string][]string
	files      int
}

func (s *scan) add(name, rule, message string) {
	s.violations = append(s.violations, violation{name, rule, message})
}

func (s *scan) file(full, name string, machine bool) error {
	base := path.Base(name)
	if path.Ext(base) != ".yaml" && path.Ext(base) != ".yml" {
		return nil
	}
	s.files++
	stem := strings.TrimSuffix(base, path.Ext(base))
	if !machine {
		stem = strings.TrimSuffix(stem, ".enc")
	}
	patch := machine || strings.Contains("/"+name, "/patches/")
	if !kebabName.MatchString(stem) && (machine || !under(name, s.cfg.FilenameExemptDirectories)) {
		s.add(name, "kebab-case", "use a lowercase kebab-case filename")
	}
	if strings.HasSuffix(stem, "-patch") {
		if patch {
			s.add(name, "patch-suffix", "drop the redundant -patch suffix")
		} else {
			s.add(name, "patch-location", "move the patch into a patches/ directory and name it by intent")
		}
	}
	docs, err := documents(full)
	if err != nil {
		return fmt.Errorf("%q: %w", name, err)
	}
	if machine {
		if len(docs) > 1 {
			s.add(name, "one-document", "split machine configuration into one YAML document per file")
		}
		if len(docs) == 1 && docs[0].kind != "" && leadsWith(stem, kebab(docs[0].kind)) {
			s.add(name, "patch-intent", "name the machine configuration by intent instead of its kind")
		}
		return nil
	}
	resources := slices.DeleteFunc(slices.Clone(docs), func(d document) bool { return d.kind == "" })
	if len(resources) > 1 {
		if !slices.Contains(s.cfg.MultiResourceFiles, name) {
			s.add(name, "one-resource", "split Kubernetes resources into separate files")
		}
		return nil
	}
	if !patch && base != "kustomization.yaml" && slices.ContainsFunc(docs, func(d document) bool { return d.kind == "" }) {
		s.add(name, "patch-location", "place kindless patch fragments in a patches/ directory")
	}
	if len(resources) == 0 {
		return nil
	}
	doc := resources[0]
	if !patch && base != "kustomization.yaml" {
		s.folders[path.Dir(name)] = append(s.folders[path.Dir(name)], doc.kind)
	}
	switch {
	case doc.kind == "Kustomization" && strings.HasPrefix(doc.api, "kustomize.toolkit.fluxcd.io/"):
		validFluxName := base == "flux-kustomization.yaml" || (strings.HasPrefix(base, "flux-kustomization-") && strings.HasSuffix(base, ".yaml"))
		if !validFluxName {
			s.add(name, "flux-filename", "use flux-kustomization.yaml or flux-kustomization-<purpose>.yaml")
		}
	case (doc.kind == "Kustomization" || doc.kind == "Component") && strings.HasPrefix(doc.api, "kustomize.config.k8s.io/"):
		if base != "kustomization.yaml" {
			s.add(name, "build-filename", "use kustomization.yaml for Kustomize build files")
		}
	case base == "kustomization.yaml" || under(name, s.cfg.CRDirectories):
		// Explicit CR directories name instances by purpose; the directory supplies the kind.
	case patch:
		if leadsWith(stem, kebab(doc.kind)) {
			s.add(name, "patch-intent", "name the patch by intent instead of its kind")
		}
	default:
		if !leadsWith(stem, kebab(doc.kind)) && !matches(name, s.cfg.KindPrefixExemptFiles) {
			s.add(name, "kind-prefix", "lead the filename with "+kebab(doc.kind)+" or "+kebab(doc.kind)+"-<purpose>")
		}
	}
	return nil
}

func validate(root string, cfg config) ([]violation, error) {
	if err := cfg.check(); err != nil {
		return nil, err
	}
	s := scan{cfg: cfg, folders: make(map[string][]string)}
	for _, group := range []struct {
		roots   []string
		machine bool
	}{{cfg.ResourceRoots, false}, {cfg.PatchRoots, true}} {
		for _, dir := range group.roots {
			full := filepath.Join(root, filepath.FromSlash(dir))
			// Check each ancestor too: WalkDir does not follow directory symlinks,
			// but a symlink in a configured root's parent would otherwise escape that rule.
			for current := dir; current != "."; current = path.Dir(current) {
				info, err := os.Lstat(filepath.Join(root, filepath.FromSlash(current)))
				if err != nil {
					return nil, fmt.Errorf("scan root %q: %w", dir, err)
				}
				if !info.IsDir() {
					return nil, fmt.Errorf("scan root %q must contain only real directories", dir)
				}
			}
			err := filepath.WalkDir(full, func(file string, entry fs.DirEntry, walkErr error) error {
				if walkErr != nil {
					return walkErr
				}
				name, err := filepath.Rel(root, file)
				if err != nil {
					return err
				}
				name = filepath.ToSlash(name)
				if entry.Type()&os.ModeSymlink != 0 {
					return fmt.Errorf("%q: symlinks are not supported in scan roots", name)
				}
				if entry.IsDir() {
					if !kebabName.MatchString(entry.Name()) {
						s.add(name, "kebab-case", "use a lowercase kebab-case directory name")
					}
					return nil
				}
				if !entry.Type().IsRegular() {
					return fmt.Errorf("%q: expected a regular file", name)
				}
				return s.file(file, name, group.machine)
			})
			if err != nil {
				return nil, fmt.Errorf("scan %q: %w", dir, err)
			}
		}
	}
	if s.files == 0 {
		return nil, errors.New("scan roots contain no YAML files")
	}
	s.grouping()
	slices.SortFunc(s.violations, func(a, b violation) int {
		if order := strings.Compare(a.Path, b.Path); order != 0 {
			return order
		}
		return strings.Compare(a.Rule, b.Rule)
	})
	return s.violations, nil
}

func (s *scan) grouping() {
	workloads := []string{"HelmRelease", "HelmRepository", "Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Pod", "Job", "CronJob", "OCIRepository", "Kustomization", "Component"}
	for dir, kinds := range s.folders {
		if len(kinds) < 2 || slices.Contains(workloads, kinds[0]) || slices.ContainsFunc(kinds, func(k string) bool { return k != kinds[0] }) {
			continue
		}
		if slices.ContainsFunc(s.cfg.CRDirectories, func(parent string) bool { return strings.HasPrefix(dir, parent+"/") }) {
			continue
		}
		if path.Base(dir) != plural(kinds[0]) {
			s.add(dir, "cr-directory", "name the directory "+plural(kinds[0])+" when grouping instances of that kind")
		}
	}
}
