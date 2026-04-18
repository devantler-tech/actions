# Update Copilot Skills

Resolve the latest ref + commit SHA for each skill in `skills-lock.json` and pin them back into the lockfile so subsequent installs are reproducible. Pairs with [`setup-copilot-skills`](../setup-copilot-skills/README.md).

For each skill the action:

1. Calls `gh api repos/<source>/releases/latest` for the newest release tag.
2. Falls back to the repository's default branch when no release exists.
3. Resolves the commit SHA for that ref via `gh api repos/<source>/commits/<ref>`.
4. Writes the resolved `ref` and `digest` (full commit SHA) back into the lockfile entry.

Run it from a scheduled workflow — the diff on `skills-lock.json` is the renovate-style "version bump" PR.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `skills-lock` | Path to the `skills-lock.json` manifest to update | ❌ | `skills-lock.json` |
| `gh-version` | Minimum required `gh` version (must support `gh skill`) | ❌ | `2.90.0` |
| `github-token` | GitHub token exposed to `gh` as `GH_TOKEN` | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `changed` | `true` when the lockfile was modified, `false` otherwise |
| `updated-skills` | Newline-separated list of `name old-digest -> new-digest` lines for skills whose pins changed |

## Usage

### Scheduled lockfile bump

```yaml
name: 🔄 Update Copilot Skills

on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch:

permissions: {}

jobs:
  update:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: true

      - id: bump
        uses: devantler-tech/actions/update-copilot-skills@main

      - if: steps.bump.outputs.changed == 'true'
        uses: peter-evans/create-pull-request@v8
        with:
          commit-message: "chore(deps): update copilot skills"
          title: "chore(deps): update copilot skills"
          body: |
            Automated update of Copilot skills.

            ```
            ${{ steps.bump.outputs.updated-skills }}
            ```
          branch: deps/copilot-skills-update
          labels: dependencies,automation
```

For a batteries-included version of the above, prefer the reusable workflow [`devantler-tech/reusable-workflows/.github/workflows/update-copilot-skills.yaml`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-copilot-skills.yaml).

## Lockfile shape

After the first run, entries gain `ref` and `digest`:

```json
{
  "version": 1,
  "skills": {
    "git-commit": {
      "source": "devantler-tech/skills",
      "sourceType": "github",
      "ref": "v0.1.1",
      "digest": "6d50a758e1f2b0c4d9a3a8c0a0a0a0a0a0a0a0a0"
    }
  }
}
```

`setup-copilot-skills` honors `digest` (preferred) or `ref` via `gh skill install --pin`, so once an entry is pinned, every subsequent CI install is reproducible.

## Requirements

- `gh` **≥ 2.90.0** on the runner. Same bootstrap behavior as `setup-copilot-skills`: if the runner image ships an older `gh`, the action downloads the required release tarball on demand (Linux and macOS, amd64/arm64). Windows runners must pre-install `gh >= 2.90.0`.
- `jq` (pre-installed on GitHub-hosted runners).
