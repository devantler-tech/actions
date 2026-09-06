package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const basicConfig = "version: 1\nresource-roots: [k8s]\n"

func TestCLI(t *testing.T) {
	for _, tc := range []struct {
		name, manifest, config, want string
		code                         int
	}{
		{"valid", deployment, basicConfig, "All manifest naming conventions satisfied", 0},
		{"violation", secret, basicConfig, "kind-prefix", 1},
		{"malformed", "kind: [secret-value\n", basicConfig, "invalid YAML", 2},
		{"duplicate metadata", "kind: Deployment\nkind: Secret\n", basicConfig, "invalid YAML mapping", 2},
		{"nonstring kind", "kind: 123\n", basicConfig, "kind must be a nonempty string", 2},
		{"nonstring mapping key", "kind: Deployment\nfalse: value\n", basicConfig, "mapping keys must be strings", 2},
		{"unknown configuration", deployment, basicConfig + "resource-root: [other]\n", "documented fields", 2},
		{"empty configuration", deployment, "", "configuration", 2},
		{"unknown version", deployment, "version: 2\nresource-roots: [k8s]\n", "version", 2},
		{"missing root", deployment, "version: 1\nresource-roots: [missing]\n", "scan root", 2},
		{"missing roots", deployment, "version: 1\n", "at least one", 2},
		{"parent traversal", deployment, "version: 1\nresource-roots: [../k8s]\n", "repository-relative", 2},
		{"absolute path", deployment, "version: 1\nresource-roots: [/k8s]\n", "repository-relative", 2},
		{"overlapping roots", deployment, "version: 1\nresource-roots: [k8s]\npatch-roots: [k8s/app]\n", "overlap", 2},
		{"overlapping expanded roots", deployment, "version: 1\nresource-roots: ['k*', k8s/app]\n", "overlap", 2},
		{"unmatched root pattern", deployment, "version: 1\npatch-roots: ['talos*']\n", "scan root", 2},
		{"configuration stream", deployment, basicConfig + "---\nversion: 1\n", "exactly one", 2},
		{"configuration glob typo", deployment, basicConfig + "kind-prefix-exempt-files: ['[']\n", "invalid path pattern", 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			root := writeFiles(t, map[string]string{"k8s/app/deployment.yaml": tc.manifest, ".github/naming.yaml": tc.config})
			var stdout, stderr bytes.Buffer
			got := run([]string{"--root", root, "--config", ".github/naming.yaml"}, &stdout, &stderr)
			output := stdout.String() + stderr.String()
			if got != tc.code || !strings.Contains(output, tc.want) {
				t.Fatalf("exit=%d output=%q; want exit=%d containing %q", got, output, tc.code, tc.want)
			}
			if strings.Contains(output, "secret-value") {
				t.Fatal("manifest content leaked into error output")
			}
		})
	}
}

func TestCLIArguments(t *testing.T) {
	for _, args := range [][]string{{}, {"--unknown"}, {"--config", "missing", "unexpected"}} {
		var stdout, stderr bytes.Buffer
		if got := run(args, &stdout, &stderr); got != 2 {
			t.Fatalf("args=%q returned %d, want 2", args, got)
		}
	}
}

func TestSymlinksAndEmptyRootsFail(t *testing.T) {
	for _, kind := range []string{"file", "root", "ancestor", "empty"} {
		t.Run(kind, func(t *testing.T) {
			root := writeFiles(t, map[string]string{"original/deployment.yaml": deployment, "k8s/.keep": ""})
			cfg := config{Version: 1, ResourceRoots: []string{"k8s"}}
			switch kind {
			case "file":
				if err := os.Symlink(filepath.Join(root, "original/deployment.yaml"), filepath.Join(root, "k8s/deployment.yaml")); err != nil {
					t.Fatal(err)
				}
			case "root", "ancestor":
				if err := os.Symlink(filepath.Join(root, "original"), filepath.Join(root, "linked")); err != nil {
					t.Fatal(err)
				}
				cfg.ResourceRoots = []string{"linked"}
				if kind == "ancestor" {
					cfg.ResourceRoots = []string{"linked/child"}
				}
			}
			if _, err := validate(root, cfg); err == nil {
				t.Fatal("expected error instead of a silently empty or external scan")
			}
		})
	}
}

func TestKebabAndPlural(t *testing.T) {
	for kind, want := range map[string]string{"VerticalPodAutoscaler": "vertical-pod-autoscalers", "HTTPScaledObject": "http-scaled-objects", "ClusterPolicy": "cluster-policies", "Ingress": "ingresses", "EndpointSlice": "endpoint-slices", "Endpoints": "endpoints", "SecurityContextConstraints": "security-context-constraints"} {
		if got := plural(kind); got != want {
			t.Errorf("plural(%s)=%s, want %s", kind, got, want)
		}
	}
}
