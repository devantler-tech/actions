# Enable Auto Merge on PR

Approve and auto-merge PRs from specific bots/users. Generates an authenticated token using GitHub App credentials, approves the pull request, and enables auto-merge with squash strategy.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `app-id` | GitHub App ID | ✅ | - |
| `app-private-key` | GitHub App Private Key | ✅ | - |
| `github-token` | GitHub Token | ✅ | - |

## Usage

```yaml
steps:
  - name: Enable auto-merge
    uses: devantler-tech/actions/enable-auto-merge-on-pr@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
```
