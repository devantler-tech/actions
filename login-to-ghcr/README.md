# Login to GHCR

Login to GitHub Container Registry (GHCR) for pulling or pushing container images.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `token` | GitHub token with `packages:read` (or `packages:write`) scope | ✅ | - |

## Usage

```yaml
steps:
  - name: Login to GHCR
    uses: devantler-tech/actions/login-to-ghcr@main
    with:
      token: ${{ secrets.GITHUB_TOKEN }}
```
