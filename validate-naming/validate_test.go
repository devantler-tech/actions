package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

const deployment = "apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: app\n"
const secret = "apiVersion: v1\nkind: Secret\nmetadata:\n  name: settings\n"
const flux = "apiVersion: kustomize.toolkit.fluxcd.io/v1\nkind: Kustomization\n"
const build = "apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n"

func writeFiles(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	for path, content := range files {
		full := filepath.Join(root, filepath.FromSlash(path))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestNamingRules(t *testing.T) {
	cases := []struct {
		name  string
		files map[string]string
		cfg   config
		want  string
	}{
		{name: "resource without leading separator", files: map[string]string{"k8s/app/deployment.yaml": deployment}},
		{name: "kind prefix required without separator", files: map[string]string{"k8s/app/wrong.yaml": deployment}, want: "kind-prefix"},
		{name: "directory kebab case", files: map[string]string{"k8s/BadDir/deployment.yaml": deployment}, want: "kebab-case"},
		{name: "file kebab case", files: map[string]string{"k8s/app/Deployment.yaml": deployment}, want: "kebab-case"},
		{name: "encrypted YAML suffix", files: map[string]string{"k8s/app/secret.enc.yaml": secret}},
		{name: "two resources", files: map[string]string{"k8s/app/deployment.yaml": deployment + "--- # next\n" + secret}, want: "one-resource"},
		{name: "empty documents ignored", files: map[string]string{"k8s/app/deployment.yaml": "---\n# comment\n---\n" + deployment + "---\n"}},
		{name: "quoted metadata", files: map[string]string{"k8s/app/deployment.yaml": "apiVersion: 'apps/v1' # comment\nkind: \"Deployment\" # comment\n"}},
		{name: "CRLF documents", files: map[string]string{"k8s/app/deployment.yaml": "kind: Deployment\r\n--- # next\r\nkind: Secret\r\n"}, want: "one-resource"},
		{name: "flow mapping", files: map[string]string{"k8s/app/wrong.yaml": "{apiVersion: apps/v1, kind: Deployment}\n"}, want: "kind-prefix"},
		{name: "block scalar separator is content", files: map[string]string{"k8s/app/config-map.yaml": "kind: ConfigMap\ndata:\n  text: |\n    ---\n    kind: Secret\n"}},
		{name: "bundle exception", files: map[string]string{"k8s/vendor/operator.yaml": deployment + "---\n" + secret}, cfg: config{MultiResourceFiles: []string{"k8s/vendor/operator.yaml"}}},
		{name: "bundle exception is exact", files: map[string]string{"k8s/vendor/operator-extra.yaml": deployment + "---\n" + secret}, cfg: config{MultiResourceFiles: []string{"k8s/vendor/operator.yaml"}}, want: "one-resource"},
		{name: "Flux prefix", files: map[string]string{"k8s/app/flux-kustomization.yaml": flux}},
		{name: "Flux purpose", files: map[string]string{"k8s/app/flux-kustomization-app.yaml": flux}},
		{name: "Flux rejects glued prefix", files: map[string]string{"k8s/app/flux-kustomizationapp.yaml": flux}, want: "flux-filename"},
		{name: "Flux filename remains exact", files: map[string]string{"k8s/app/flux-kustomization.enc.yaml": flux}, want: "flux-filename"},
		{name: "Flux cannot masquerade as build", files: map[string]string{"k8s/app/kustomization.yaml": flux}, want: "flux-filename"},
		{name: "build name", files: map[string]string{"k8s/app/kustomization.yaml": build}},
		{name: "build name required", files: map[string]string{"k8s/app/flux-kustomization.yaml": build}, want: "build-filename"},
		{name: "Component build name", files: map[string]string{"k8s/app/kustomization.yaml": "apiVersion: kustomize.config.k8s.io/v1alpha1\nkind: Component\n"}},
		{name: "kindless build", files: map[string]string{"k8s/app/kustomization.yaml": "resources: [deployment.yaml]\n"}},
		{name: "kindless outside patches", files: map[string]string{"k8s/app/enable-feature.yaml": "spec:\n  enabled: true\n"}, want: "patch-location"},
		{name: "JSON6902 in patches", files: map[string]string{"k8s/app/patches/enable-feature.yaml": "- op: add\n  path: /spec/enabled\n  value: true\n"}},
		{name: "JSON6902 outside patches", files: map[string]string{"k8s/app/enable-feature.yaml": "- op: remove\n  path: /spec/enabled\n"}, want: "patch-location"},
		{name: "patch intent", files: map[string]string{"k8s/app/patches/enable-feature.yaml": deployment}},
		{name: "patch kind prefix rejected", files: map[string]string{"k8s/app/patches/deployment-feature.yaml": deployment}, want: "patch-intent"},
		{name: "patch redundant suffix", files: map[string]string{"k8s/app/patches/enable-feature-patch.yaml": deployment}, want: "patch-suffix"},
		{name: "misplaced patch suffix", files: map[string]string{"k8s/app/deployment-patch.yaml": deployment}, want: "patch-location"},
		{name: "Flux patch keeps prefix", files: map[string]string{"k8s/app/patches/flux-kustomization.yaml": flux}},
		{name: "configured CR directory", files: map[string]string{"k8s/cluster-policies/deny-root.yaml": "kind: ClusterPolicy\n"}, cfg: config{CRDirectories: []string{"k8s/cluster-policies"}}},
		{name: "CR prefix boundary", files: map[string]string{"k8s/cluster-policies-other/deny-root.yaml": "kind: ClusterPolicy\n"}, cfg: config{CRDirectories: []string{"k8s/cluster-policies"}}, want: "kind-prefix"},
		{name: "plural folder", files: map[string]string{"k8s/cluster-policies/cluster-policy-a.yaml": "kind: ClusterPolicy\n", "k8s/cluster-policies/cluster-policy-b.yaml": "kind: ClusterPolicy\n"}},
		{name: "wrong plural folder", files: map[string]string{"k8s/policies/cluster-policy-a.yaml": "kind: ClusterPolicy\n", "k8s/policies/cluster-policy-b.yaml": "kind: ClusterPolicy\n"}, want: "cr-directory"},
		{name: "workload group", files: map[string]string{"k8s/app/deployment-a.yaml": deployment, "k8s/app/deployment-b.yaml": deployment}},
		{name: "CR organizational subfolder", files: map[string]string{"k8s/cluster-policies/security/deny-root.yaml": "kind: ClusterPolicy\n", "k8s/cluster-policies/security/deny-host.yaml": "kind: ClusterPolicy\n"}, cfg: config{CRDirectories: []string{"k8s/cluster-policies"}}},
		{name: "instance-owned pattern", files: map[string]string{"k8s/clusters/prod/variables-secret.enc.yaml": secret}, cfg: config{KindPrefixExemptFiles: []string{"k8s/clusters/*/variables-secret.enc.yaml"}}},
		{name: "instance-owned exception stays narrow", files: map[string]string{"k8s/clusters/prod/wrong.yaml": secret}, cfg: config{KindPrefixExemptFiles: []string{"k8s/clusters/*/variables-secret.enc.yaml"}}, want: "kind-prefix"},
		{name: "vendor filename exception", files: map[string]string{"k8s/custom-resource-definitions/tests.example.io.yaml": "kind: CustomResourceDefinition\n"}, cfg: config{CRDirectories: []string{"k8s/custom-resource-definitions"}, FilenameExemptDirectories: []string{"k8s/custom-resource-definitions"}}},
		{name: "Talos intent", files: map[string]string{"talos/enable-feature.yaml": "machine:\n  features: {}\n"}, cfg: config{PatchRoots: []string{"talos"}}},
		{name: "new Talos environments are covered", files: map[string]string{"talos/enable-feature.yaml": "machine: {}\n", "talos-staging/hostname-config.yaml": "kind: HostnameConfig\n"}, cfg: config{PatchRoots: []string{"talos*"}}, want: "patch-intent"},
		{name: "root patterns select directories", files: map[string]string{"talos/enable-feature.yaml": "machine: {}\n", "talosconfig": "not a manifest\n"}, cfg: config{PatchRoots: []string{"talos*"}}},
		{name: "Talos kind prefix", files: map[string]string{"talos/hostname-config.yaml": "apiVersion: v1alpha1\nkind: HostnameConfig\n"}, cfg: config{PatchRoots: []string{"talos"}}, want: "patch-intent"},
		{name: "Talos multiple kindless docs", files: map[string]string{"talos/enable-feature.yaml": "machine: {}\n---\ncluster: {}\n"}, cfg: config{PatchRoots: []string{"talos"}}, want: "one-document"},
		{name: "Talos redundant suffix", files: map[string]string{"talos/enable-feature-patch.yaml": "machine: {}\n"}, cfg: config{PatchRoots: []string{"talos"}}, want: "patch-suffix"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			root := writeFiles(t, tc.files)
			if len(tc.cfg.PatchRoots) == 0 {
				tc.cfg.ResourceRoots = []string{"k8s"}
			}
			tc.cfg.Version = 1
			got, err := validate(root, tc.cfg)
			if err != nil {
				t.Fatal(err)
			}
			if tc.want == "" && len(got) != 0 {
				t.Fatalf("unexpected violations: %+v", got)
			}
			if tc.want != "" && !slices.ContainsFunc(got, func(v violation) bool { return v.Rule == tc.want }) {
				t.Fatalf("wanted %s violation, got %+v", tc.want, got)
			}
			for _, v := range got {
				if v.Path == "" {
					t.Fatal("diagnostic missing path")
				}
			}
		})
	}
}
