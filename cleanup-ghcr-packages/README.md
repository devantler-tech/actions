# Cleanup GHCR Packages

Clean up old GitHub Container Registry (GHCR) packages. Removes container images older than the specified duration while preserving the most recent tagged images.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `older-than` | Delete images older than this duration | ❌ | `1 year` |
| `keep-n-tagged` | Number of tagged images to keep | ❌ | `10` |
| `package` | Package to clean up. Defaults to the calling repository's package (resolved by the underlying cleanup action) | ❌ | `repository name` |
| `dry-run` | Simulate the cleanup without deleting anything (`true`/`false`) | ❌ | `false` |

## Usage

### Default retention policy

```yaml
steps:
  - name: Cleanup old GHCR packages
    uses: devantler-tech/actions/cleanup-ghcr-packages@main
```

### Custom retention policy

```yaml
steps:
  - name: Cleanup old GHCR packages
    uses: devantler-tech/actions/cleanup-ghcr-packages@main
    with:
      older-than: "3 months"
      keep-n-tagged: "15"
```

### Dry run

Preview what would be deleted without removing anything. Recommended before a first real run.

```yaml
steps:
  - name: Preview GHCR cleanup
    uses: devantler-tech/actions/cleanup-ghcr-packages@main
    with:
      package: "my-app"
      dry-run: "true"
```
