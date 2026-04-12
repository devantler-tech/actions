# DevantlerTech GitHub Actions

> [!NOTE]
> For reusable workflows, see [devantler-tech/reusable-workflows](https://github.com/devantler-tech/reusable-workflows).

Composite actions for CI/CD pipelines across DevantlerTech projects.

```mermaid
---
title: GitHub Actions Relationship Diagram
---
flowchart TD
  A[Workflows] --> B[Jobs]
  B --> C([Reusable Workflows])
  B --> D[Steps]
  C --> D
  C --> B
  D --> E[***Actions***]
  E -.- F([***Composite Actions***])
  F --> D
  E -.- G([***JavaScript Actions***])
  E -.- H([***Docker Container Actions***])
```

## Actions

| Action | Description |
|--------|-------------|
| [cleanup-ghcr-packages](cleanup-ghcr-packages/README.md) | Clean up old GHCR packages |
| [create-issues-from-todos](create-issues-from-todos/README.md) | Create GitHub issues from TODO comments |
| [enable-auto-merge-on-pr](enable-auto-merge-on-pr/README.md) | Approve and auto-merge PRs from trusted bots/users |
| [login-to-ghcr](login-to-ghcr/README.md) | Login to GitHub Container Registry |
| [run-dotnet-tests](run-dotnet-tests/README.md) | Test .NET solution or project with coverage |
| [setup-go-toolchain](setup-go-toolchain/README.md) | Setup Go with optional private module support |
| [setup-ksail-cli](setup-ksail-cli/README.md) | Install KSail CLI via Homebrew |
| [sync-github-labels](sync-github-labels/README.md) | Sync GitHub labels from a configuration file |
| [upsert-issue](upsert-issue/README.md) | Create, update, reopen, or close a GitHub issue by title |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and guidelines.
