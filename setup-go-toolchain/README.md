# Setup Go Toolchain

Setup Go with private module discovery for devantler-tech repositories.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `go-version` | Go version to install | ❌ | `stable` |
| `github-token` | Deprecated and ignored; retained for compatibility | ❌ | - |

## Outputs

| Name | Description |
|------|-------------|
| `go-version` | The resolved Go version that was installed |

## Usage

### Default Go version

```yaml
steps:
  - name: Setup Go
    uses: devantler-tech/actions/setup-go-toolchain@main
```

### Specific version

```yaml
steps:
  - name: Setup Go
    uses: devantler-tech/actions/setup-go-toolchain@main
    with:
      go-version: "1.26"
```

### With private module support

The action configures `GOPRIVATE` so the Go toolchain recognizes
`github.com/devantler-tech/*` as private. Configure authentication separately in
a trusted step that limits the credential to the operation that needs it. The
action intentionally does not accept or persist a token because later steps can
read credentials stored in the runner's Git configuration.

```yaml
steps:
  - name: Setup Go
    uses: devantler-tech/actions/setup-go-toolchain@main
```
