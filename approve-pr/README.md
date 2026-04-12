# Approve PR

Approve a pull request using a GitHub App identity. This is needed because `GITHUB_TOKEN` cannot provide independent approvals that satisfy branch protection rules requiring multiple reviewers.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `app-id` | GitHub App ID | ✅ | - |
| `app-private-key` | GitHub App Private Key | ✅ | - |
| `pr-number` | Pull request number to approve | ✅ | - |
| `dry-run` | Validate only; do not approve the pull request | - | `false` |

## Usage

### Approve a PR from a trusted bot

```yaml
steps:
  - name: Approve PR
    uses: devantler-tech/actions/approve-pr@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      pr-number: ${{ github.event.pull_request.number }}
```

### Combined with auto-merge

```yaml
steps:
  - name: Approve PR
    uses: devantler-tech/actions/approve-pr@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      pr-number: ${{ github.event.pull_request.number }}

  - name: Enable auto-merge
    uses: devantler-tech/actions/enable-auto-merge-on-pr@main
    with:
      pr-number: ${{ github.event.pull_request.number }}
```
