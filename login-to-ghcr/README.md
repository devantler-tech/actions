# Login to GHCR

> **Frozen legacy reference.** For new integrations and contributions, use the
> [maintained login-to-ghcr guide](https://github.com/devantler-tech/.github/blob/main/actions/login-to-ghcr/README.md)
> and [contribution guide](https://github.com/devantler-tech/.github/blob/main/CONTRIBUTING.md).
> The examples below describe legacy consumers, not a new-setup recommendation.
> Keep existing calls pinned to a reviewed full commit SHA; do not copy floating
> refs or change a consumer's automation without reviewing its migration.

Login to GitHub Container Registry (GHCR) for pulling or pushing container images.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `github-token` | GitHub token with `packages:read` (or `packages:write`) scope | ✅ | - |

## Usage

```yaml
steps:
  - name: Login to GHCR
    uses: devantler-tech/actions/login-to-ghcr@main
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```
