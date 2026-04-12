# Enable Auto Merge on PR

Enable auto-merge on a pull request using GitHub CLI. The PR will only merge automatically once all required status checks pass and branch protection rules are satisfied.

- **Auto-merge must be enabled** on the repository (Settings > Pull Requests > Allow auto-merge). If not enabled, a warning is displayed but the action does not fail.
- Supports `merge`, `squash`, and `rebase` merge methods.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `pr-number` | Pull request number to enable auto-merge on | ✅ | - |
| `merge-method` | Merge method to use: `merge`, `squash`, or `rebase` | - | `squash` |
| `dry-run` | Validate only; do not enable auto-merge | - | `false` |

## Usage

```yaml
steps:
  - name: Enable auto-merge
    uses: devantler-tech/actions/enable-auto-merge-on-pr@main
    with:
      pr-number: ${{ github.event.pull_request.number }}
      merge-method: squash
```

> **Note:** This action uses `github.token` from context for authentication. Ensure the job has `contents: write` and `pull-requests: write` permissions.
