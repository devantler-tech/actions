# DevantlerTech GitHub Actions 🚀

> [!NOTE]
> To see DevantlerTech's Reusable Workflows, please visit the [devantler-tech/reusable-workflows](https://github.com/devantler-tech/reusable-workflows) repository.

Welcome to the DevantlerTech GitHub Actions repository! This repository contains [actions](#composite-actions) designed to streamline your CI/CD processes.  These actions are used across all DevantlerTech projects, ensuring consistency and efficiency.

The below diagram illustrates the relationship between GitHub Workflows and GitHub Actions.

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

[Actions](https://docs.github.com/en/actions/tutorials/creating-a-composite-action) are a powerful way to group multiple steps into a single action. They allow composing small, reusable components that can be used in any GitHub Actions context, e.g, within reusable workflows, standalone workflows, or even in other GitHub Actions.

- **[Auto Merge Action](auto-merge-action/README.md)** - Composite action to approve and auto-merge PRs from specific bots/users
- **[Cleanup GHCR Action](cleanup-ghcr-action/README.md)** - Clean up old GitHub Container Registry (GHCR) packages
- **[.NET Test Action](dotnet-test-action/README.md)** - Test .NET solution or project
- **[Setup KSail Action](setup-ksail-action/README.md)** - Installs KSail CLI via Homebrew
- **[Sync Labels Action](sync-labels-action/README.md)** - Sync GitHub labels
- **[TODOs Action](todos-action/README.md)** - A composite action to create GitHub issues from TODO comments
