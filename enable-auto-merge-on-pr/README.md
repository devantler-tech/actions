# Enable Auto Merge on PR

> **Frozen legacy reference.** For new integrations and contributions, use the
> [maintained enable-auto-merge-on-pr guide](https://github.com/devantler-tech/.github/blob/main/actions/enable-auto-merge-on-pr/README.md)
> and [contribution guide](https://github.com/devantler-tech/.github/blob/main/CONTRIBUTING.md).
> The examples below describe legacy consumers, not a new-setup recommendation.
> Keep existing calls pinned to a reviewed full commit SHA; do not copy floating
> refs or change a consumer's automation without reviewing its migration.

Enable auto-merge on a pull request using GitHub CLI. The PR will only merge automatically once all required status checks pass and branch protection rules are satisfied.

This legacy wrapper arms auto-merge; it does not provide an exact-head review
gate or prove which future head will merge. A later push can change the branch.
Use the consuming repository's current trust/review policy and confirm the
actual merged head; do not treat this step's success as completed delivery.

- **Auto-merge must be enabled** on the repository (Settings > Pull Requests > Allow auto-merge). If not enabled, a warning is displayed but the action does not fail.
- Supports `merge`, `squash`, and `rebase` merge methods.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `pr-number` | Pull request number to enable auto-merge on | ✅ | - |
| `merge-method` | Merge method to use: `merge`, `squash`, or `rebase` | - | `squash` |
| `dry-run` | Validate only; do not enable auto-merge | - | `false` |
| `token` | GitHub token used to arm auto-merge. Defaults to the workflow token; pass a GitHub App token when the resulting merge must trigger downstream workflows (a `GITHUB_TOKEN`-armed merge does not re-trigger workflows). | - | `github.token` |

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
