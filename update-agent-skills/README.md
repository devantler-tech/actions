# Update Agent Skills

Run [`gh skill update --all`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) against installed skills and report any changes. Pairs with [`setup-agent-skills`](../setup-agent-skills/README.md).

The `github-*` frontmatter that `gh skill install` injects into each `SKILL.md` (github-repo, github-path, github-ref, github-tree-sha) is the source of truth — this action asks the CLI to refresh those files against their upstreams, then reports whether any of them changed. It is agent-neutral: it operates on the `SKILL.md` files in `dir`, so it refreshes skills installed for any agent (Copilot, Claude Code, …). No lockfile.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `dir` | Directory to scan for installed skills. The action finds every `SKILL.md` under this path, uses its immediate parent (the directory containing individual skill subdirectories, e.g. `skills/`) as the `--dir` argument, and runs `gh skill update --all --dir <skills-dir>` for each unique `<skills-dir>`. This supports both the standard layout (`.agents/skills/`) and nested layouts like `plugins/<plugin>/skills/<skill>/`. | ❌ | `.` |
| `dry-run` | When `true`, pass `--dry-run` (report without modifying files) | ❌ | `false` |
| `unpin` | When `true`, pass `--unpin` (clear pinned versions and include pinned skills) | ❌ | `false` |
| `gh-version` | Minimum required `gh` version (must support `gh skill`) | ❌ | `2.90.0` |
| `github-token` | GitHub token exposed to `gh` as `GH_TOKEN` | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `changed` | `true` when at least one `SKILL.md` was modified, `false` otherwise |
| `updated-skills` | Cleaned stdout from `gh skill update --all` (blank when nothing changed) |

## Usage

### Scheduled update PR

```yaml
name: 🔄 Update Agent Skills

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

      - id: update
        uses: devantler-tech/actions/update-agent-skills@v5
        with:
          dir: .agents/skills

      - if: steps.update.outputs.changed == 'true'
        uses: peter-evans/create-pull-request@v8
        with:
          commit-message: "chore(deps): update agent skills"
          title: "chore(deps): update agent skills"
          body: |
            ```
            ${{ steps.update.outputs.updated-skills }}
            ```
          branch: deps/agent-skills-update
          labels: dependencies,automation
```

For a batteries-included version of the above, use the reusable workflow [`devantler-tech/actions/.github/workflows/update-agent-skills.yaml`](https://github.com/devantler-tech/actions/blob/main/.github/workflows/update-agent-skills.yaml).

### Plugin directory layout

For repositories that organise skills into subdirectories (e.g. a plugin marketplace):

```yaml
# plugins/
#   go/skills/golang-pro/SKILL.md
#   github/skills/github-issues/SKILL.md
#   ...

- id: update
  uses: devantler-tech/actions/update-agent-skills@v5
  with:
    dir: plugins   # discovers plugins/go/skills, plugins/github/skills, … and updates each
```

## Migrating from `update-copilot-skills` (v4 and earlier)

`update-copilot-skills` was renamed to `update-agent-skills`; its inputs, outputs, and behaviour are unchanged. Update the `uses:` reference:

```diff
- uses: devantler-tech/actions/update-copilot-skills@v4
+ uses: devantler-tech/actions/update-agent-skills@v5
   with:
     dir: .agents/skills
```

## Requirements

- A trusted runner-provided `gh` with `gh attestation` support. Same bootstrap behaviour as `setup-agent-skills`: if it is older than **2.90.0**, the action downloads the required GitHub CLI release archive on Linux or macOS (amd64/arm64) and verifies its GitHub artifact attestation before installation. Windows runners must pre-install `gh >= 2.90.0`.
