# Setup Go Toolchain

Setup Go with optional private module support for devantler-tech repositories.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `go-version` | Go version to install | ❌ | `stable` |
| `token` | GitHub token for private module access | ❌ | - |

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

```yaml
steps:
  - name: Setup Go
    uses: devantler-tech/actions/setup-go-toolchain@main
    with:
      token: ${{ secrets.GITHUB_TOKEN }}
```
