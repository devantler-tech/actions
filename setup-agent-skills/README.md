# Setup Agent Skills

Install agent skills with the [`gh skill`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/) CLI from a newline-separated list of `<owner/repo> <skill>[@pin]` entries, for **one or more agents** in a single step (e.g. GitHub Copilot and Claude Code).

`gh skill install` writes upstream provenance (`metadata.github-*`) into each installed `SKILL.md`, so no lockfile is required — checked-in skills are self-describing and [`update-agent-skills`](../update-agent-skills/README.md) or `gh skill update --all` picks up drift natively.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `skills` | Newline list of `<owner/repo> <skill>[@pin]`. `@pin` is an optional tag/branch/SHA. `#` comments and blank lines are allowed. | ✅ | — |
| `agents` | One or more agents passed to `gh skill install --agent`, separated by whitespace, commas, or newlines (e.g. `github-copilot claude-code`). Each skill is installed once per agent. See `gh skill install --help` for the full list of supported agents. | ❌ | `github-copilot` |
| `scope` | Value passed to `gh skill install --scope` (`project` or `user`) | ❌ | `project` |
| `gh-version` | Minimum required `gh` version (must support `gh skill`) | ❌ | `2.90.0` |
| `github-token` | GitHub token exposed to `gh` as `GH_TOKEN` | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `installed-skills` | Newline-separated list of `source/skill-name[@pin]` entries that were installed (listed once per skill, regardless of how many agents it was installed for) |

## Usage

```yaml
steps:
  - uses: actions/checkout@v5
  - uses: devantler-tech/actions/setup-agent-skills@v5
    with:
      # Install every skill for both Copilot and Claude Code in one step.
      agents: |
        github-copilot
        claude-code
      skills: |
        github/awesome-copilot git-commit
        fluxcd/agent-skills gitops-knowledge
        devantler-tech/agent-skills ways-of-working@v1.2.0
        # Pin with @<tag|branch|sha> or omit to track the upstream default branch.
```

Omit `agents` to install for GitHub Copilot only (the default), or set it to any single agent (e.g. `claude-code`).

## Migrating from `setup-copilot-skills` (v4 and earlier)

`setup-copilot-skills` was renamed to `setup-agent-skills` and its `agent` (singular) input became `agents` (a list). The implementation is otherwise unchanged, and a single value still works exactly as before:

```diff
- uses: devantler-tech/actions/setup-copilot-skills@v4
+ uses: devantler-tech/actions/setup-agent-skills@v5
    with:
-     agent: github-copilot
+     agents: github-copilot   # or: "github-copilot claude-code" to install for both
      skills: |
        github/awesome-copilot git-commit
```

`gh skill` is agent-neutral — the same `SKILL.md` files work across Copilot, Claude Code, Cursor, Codex, Gemini CLI, and the other agents it supports — so the action is no longer Copilot-specific.

## Requirements

- `gh` **≥ 2.90.0** on the runner (with `gh skill` support). If the runner image ships an older `gh`, this action downloads the required release tarball on demand (Linux and macOS, amd64/arm64). Windows runners must pre-install `gh >= 2.90.0`.
