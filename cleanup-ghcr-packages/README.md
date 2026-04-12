# Cleanup GHCR Packages

Clean up old GitHub Container Registry (GHCR) packages. Removes container images older than the specified duration while preserving the most recent tagged images.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `older-than` | Delete images older than this duration | ❌ | `1 year` |
| `keep-n-tagged` | Number of tagged images to keep | ❌ | `10` |

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
