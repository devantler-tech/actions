# Setup Copilot Skills

Install agent skills with the [`gh skill`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) CLI from a newline-separated list of `<owner/repo> <skill>[@pin]` entries.

`gh skill install` writes upstream provenance (`metadata.github-*`) into each installed `SKILL.md`, so no lockfile is required — checked-in skills are self-describing and [`update-copilot-skills`](../update-copilot-skills/README.md) or `gh skill update --all` picks up drift natively.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `skills` | Newline list of `<owner/repo> <skill>[@pin]`. `@pin` is an optional tag/branch/SHA. `#` comments and blank lines are allowed. | ✅ | — |
| `agent` | Value passed to `gh skill install --agent` | ❌ | `github-copilot` |
| `scope` | Value passed to `gh skill install --scope` (`project` or `user`) | ❌ | `project` |
| `gh-version` | Minimum required `gh` version (must support `gh skill`) | ❌ | `2.90.0` |
| `github-token` | GitHub token exposed to `gh` as `GH_TOKEN` | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `installed-skills` | Newline-separated list of `source/skill-name[@pin]` entries that were installed |

## Usage

```yaml
steps:
  - uses: actions/checkout@v5
  - uses: devantler-tech/actions/setup-copilot-skills@v2
    with:
      skills: |
        github/awesome-copilot git-commit
        github/awesome-copilot gh-cli@v1.2.0
        fluxcd/agent-skills gitops-knowledge
        # Pin with @<tag|branch|sha> or omit to track the upstream default branch.
```

## Migrating from v1

v1 took either a `skills-lock.json` or a single `source` + `skills` list. v2 drops both inputs in favour of one flat `skills` list so consumers can mix upstreams freely:

```diff
 - uses: devantler-tech/actions/setup-copilot-skills@v1
   with:
-    source: devantler-tech/skills
-    skills: |
-      git-commit
-      gh-cli
+ uses: devantler-tech/actions/setup-copilot-skills@v2
+   with:
+     skills: |
+       github/awesome-copilot git-commit
+       github/awesome-copilot gh-cli
```

Reproducible installs no longer need a lockfile — pin each line with `@<sha>` (or `@<tag>`) and `gh skill update --all` (via the sibling [`update-copilot-skills`](../update-copilot-skills/README.md) action) edits those pins in place when upstream advances.

## Requirements

- `gh` **≥ 2.90.0** on the runner (with `gh skill` support). If the runner image ships an older `gh`, this action downloads the required release tarball on demand (Linux and macOS, amd64/arm64). Windows runners must pre-install `gh >= 2.90.0`.
