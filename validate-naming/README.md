# Validate manifest naming

Enforce shared naming conventions for Kubernetes resources and machine configuration
patches. Repository-specific roots and exceptions live in a versioned YAML file.
Validation reads files without modifying them or contacting a cluster.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `enabled` | Opt in to validation; accepts exactly `true` or `false`. | No | `false` |
| `config-file` | Configuration path, relative to `working-directory` or absolute. | No | `.github/manifest-naming.yaml` |
| `working-directory` | Repository directory, relative to `GITHUB_WORKSPACE` or absolute. | No | `.` |

## Outputs

| Name | Description |
|------|-------------|
| `validated` | `true` after successful validation; empty when disabled or unsuccessful. |

## Usage

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false
  - uses: devantler-tech/actions/validate-naming@<full-commit-sha>
    with:
      enabled: "true"
```

The temporary `enabled` input defaults off during the initial rollout; omission
does not read configuration, install Go, or scan files. Rollout and input retirement
are tracked in [#1200](https://github.com/devantler-tech/actions/issues/1200).

Enabled runs install the Go version declared in this action's `go.mod`, download
its checksum-pinned YAML dependency with bounded retries, and build from the
action's own module. The caller's Go module and workspace files are not used.
The build needs network access to the Go distribution/module services; subsequent
validation is offline. Linux and macOS runners are supported.

## Configuration

Create `.github/manifest-naming.yaml` in the repository being checked:

```yaml
version: 1
resource-roots: [k8s]
patch-roots: [talos, talos-local]
cr-directories:
  - k8s/infrastructure/cluster-policies
multi-resource-files:
  - k8s/controllers/example/operator.yaml
kind-prefix-exempt-files:
  - k8s/clusters/*/bootstrap/variables-secret.enc.yaml
filename-exempt-directories:
  - k8s/controllers/example/custom-resource-definitions
```

`version` must be `1`. At least one scan root is required. Roots must exist, be
non-overlapping directories, and collectively contain at least one `.yaml` or
`.yml` file. Paths use `/`, are relative to the repository root, and cannot contain
`..`, absolute paths, or symlinks. Unknown configuration fields, malformed YAML,
and multiple configuration documents fail validation.

| Field | Scope |
|-------|-------|
| `resource-roots` | Directories recursively checked as Kubernetes manifests. |
| `patch-roots` | Directories recursively checked as machine configuration patches. |
| `cr-directories` | Directories whose resource files use instance/purpose names; descendants inherit this exception. |
| `multi-resource-files` | Exact files exempt only from the one-resource rule, for upstream bundles. |
| `kind-prefix-exempt-files` | Files exempt only from the ordinary resource kind prefix. Supports Go `path.Match` patterns: `*` stays within one path segment; `**` has no special meaning. |
| `filename-exempt-directories` | Directories whose YAML filename stems may retain upstream names. Other checks still apply. |

All lists are optional except that `resource-roots` and `patch-roots` cannot both
be empty. Exception paths may be absent, allowing configurations to retain an
exception when a provider component is not present. Patterns are supported only
in `kind-prefix-exempt-files`; the other lists contain exact paths.

The [Platform](examples/platform.yaml) and
[platform-template](examples/platform-template.yaml) configurations illustrate
the two original consumers. Copy and maintain the applicable configuration in
the consumer; these examples are not live defaults.

## Rules

1. Directory names and YAML filename stems use lowercase kebab-case. Kubernetes
   `.enc.yaml` and `.enc.yml` files keep their encryption suffix.
2. Kubernetes files contain at most one kind-bearing resource, except declared
   upstream bundles. Empty and comment-only documents do not count.
3. Flux `Kustomization` resources use `flux-kustomization.yaml` or
   `flux-kustomization-<purpose>.yaml`.
4. Kustomize build `Kustomization` and `Component` files use `kustomization.yaml`.
5. Ordinary resource filenames lead with their kebab-cased kind, optionally
   followed by `-<purpose>`. CR directories and configured files are exempt.
6. A directory with two or more files of one non-workload kind uses the kind's
   kebab-case plural. Organizational descendants of configured CR directories
   are exempt. Component/workload kinds follow the original gates' conventions.
7. Kindless Kubernetes patch fragments belong in `patches/`; kindless
   `kustomization.yaml` build files are allowed.
8. Patches use intent names without a kind prefix or redundant `-patch` suffix.
   Flux patches retain the Flux filename convention.
9. Machine configuration patches use intent names and contain at most one
   nonempty YAML document, including documents without a kind.

The parser handles document streams with or without a leading `---`, quoted
metadata, CRLF endings, and separators inside block scalars. Invalid YAML and
duplicate mapping keys fail instead of being silently skipped. Diagnostics print
paths and rule guidance, never whole manifests or parser excerpts.

## Local validation

With an Actions checkout at the revision used by CI and Go installed:

```bash
GOWORK=off go -C /path/to/actions/validate-naming run -mod=readonly . \
  --root /path/to/consumer --config .github/manifest-naming.yaml
```

The CLI always validates; the rollout gate belongs to the composite action.
Exit codes are `0` for success, `1` for naming violations, and `2` for invalid
configuration, YAML, arguments, or filesystem errors.

Run the validator's tests with:

```bash
go -C validate-naming test -race -cover ./...
go -C validate-naming vet ./...
```
