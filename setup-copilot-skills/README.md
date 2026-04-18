# Setup Copilot Skills

Install agent skills with the [`gh skill`](https://github.com/cli/cli) CLI — from a `skills-lock.json` manifest or an inline source/skills list. Works with any `gh skill`-compatible skills repository (e.g. [`devantler-tech/skills`](https://github.com/devantler-tech/skills)).

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `skills-lock` | Path to a `skills-lock.json` manifest (used when `source` is empty) | ❌ | `skills-lock.json` |
| `source` | Single skills repo (e.g. `devantler-tech/skills`). When set, `skills` is required and `skills-lock` is ignored. | ❌ | - |
| `skills` | Newline- or comma-separated skill names to install from `source` | ❌ | - |
| `agent` | Value passed to `gh skill install --agent` | ❌ | `github-copilot` |
| `scope` | Value passed to `gh skill install --scope` (`user` or `repo`) | ❌ | `user` |
| `gh-version` | Minimum required `gh` version (must support `gh skill`) | ❌ | `2.90.0` |
| `github-token` | GitHub token exposed to `gh` as `GH_TOKEN` | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `installed-skills` | Newline-separated list of `source/skill-name` pairs that were installed |

## Usage

### From a `skills-lock.json` manifest (recommended)

```yaml
steps:
  - uses: actions/checkout@v5
  - name: Install Copilot skills
    uses: devantler-tech/actions/setup-copilot-skills@main
```

A `skills-lock.json` has the following shape:

```json
{
  "version": 1,
  "skills": {
    "git-commit": { "source": "devantler-tech/skills", "sourceType": "github" },
    "gh-cli":     { "source": "devantler-tech/skills", "sourceType": "github" }
  }
}
```

Entries may also carry an optional `ref` (release tag or branch name) and `digest` (full commit SHA). When either is present, this action installs at the pinned ref via `gh skill install --pin <digest|ref>` (`digest` wins when both are set), making installs reproducible:

```json
{
  "git-commit": {
    "source": "devantler-tech/skills",
    "sourceType": "github",
    "ref": "v0.1.1",
    "digest": "6d50a758e1f2b0c4d9a3a8c0a0a0a0a0a0a0a0a0"
  }
}
```

Use the sibling [`update-copilot-skills`](../update-copilot-skills/README.md) action to populate and bump these pins from a scheduled workflow.

### From an inline list of skills

```yaml
steps:
  - name: Install specific skills
    uses: devantler-tech/actions/setup-copilot-skills@main
    with:
      source: devantler-tech/skills
      skills: |
        git-commit
        gh-cli
        refactor
```

### Customising agent and scope

```yaml
steps:
  - uses: devantler-tech/actions/setup-copilot-skills@main
    with:
      source: devantler-tech/skills
      skills: git-commit
      agent: github-copilot
      scope: repo
```

### Inside a scheduled update workflow

For a batteries-included scheduled updater that opens a PR with any skill changes, use the companion reusable workflow [`devantler-tech/reusable-workflows/.github/workflows/update-copilot-skills.yaml`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-copilot-skills.yaml). To resolve and pin the latest skill refs back into `skills-lock.json` (so consumers get reproducible installs), use [`update-copilot-skills`](../update-copilot-skills/README.md).

## Requirements

- `gh` **≥ 2.90.0** on the runner (with `gh skill` support). If the runner image ships an older `gh`, this action downloads the required release tarball on demand (Linux and macOS, amd64/arm64). Windows runners must pre-install `gh >= 2.90.0`.
- `jq` (pre-installed on GitHub-hosted runners) when using a `skills-lock.json`.
