# Update Copilot Skills

Run [`gh skill update --all`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) against installed skills and report any changes. Pairs with [`setup-copilot-skills`](../setup-copilot-skills/README.md).

The `github-*` frontmatter that `gh skill install` injects into each `SKILL.md` (github-repo, github-path, github-ref, github-tree-sha) is the source of truth — this action asks the CLI to refresh those files against their upstreams, then reports whether any of them changed. No lockfile.

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

      - id: update
        uses: devantler-tech/actions/update-copilot-skills@v2
        with:
          dir: .agents/skills

      - if: steps.update.outputs.changed == 'true'
        uses: peter-evans/create-pull-request@v8
        with:
          commit-message: "chore(deps): update copilot skills"
          title: "chore(deps): update copilot skills"
          body: |
            ```
            ${{ steps.update.outputs.updated-skills }}
            ```
          branch: deps/copilot-skills-update
          labels: dependencies,automation
```

For a batteries-included version of the above, use the reusable workflow [`devantler-tech/reusable-workflows/.github/workflows/update-copilot-skills.yaml`](https://github.com/devantler-tech/reusable-workflows/blob/main/.github/workflows/update-copilot-skills.yaml).

### Plugin directory layout

For repositories that organise skills into subdirectories (e.g. copilot-plugins):

```yaml
# plugins/
#   go/skills/golang-pro/SKILL.md
#   github/skills/gh-cli/SKILL.md
#   ...

- id: update
  uses: devantler-tech/actions/update-copilot-skills@v2
  with:
    dir: plugins   # discovers plugins/go/skills, plugins/github/skills, … and updates each
```

## Migrating from v1

v1 resolved refs against a `skills-lock.json` manifest and wrote pins back into it. v2 delegates to `gh skill update --all` directly, operating on the installed `SKILL.md` files themselves:

```diff
 - id: update
-  uses: devantler-tech/actions/update-copilot-skills@v1
-  with:
-    skills-lock: skills-lock.json
+  uses: devantler-tech/actions/update-copilot-skills@v2
+  with:
+    dir: .agents/skills
```

Delete any `skills-lock.json` in your repo — the upstream source/ref/tree SHA now lives in each skill's frontmatter.

## Requirements

- `gh` **≥ 2.90.0** on the runner. Same bootstrap behaviour as `setup-copilot-skills`: if the runner image ships an older `gh`, the action downloads the required release tarball on demand (Linux and macOS, amd64/arm64). Windows runners must pre-install `gh >= 2.90.0`.
