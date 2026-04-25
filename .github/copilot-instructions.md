# Copilot Instructions for devantler-tech/actions

Composite GitHub Actions library for CI/CD pipelines across DevantlerTech projects. Sibling repo to [reusable-workflows](https://github.com/devantler-tech/reusable-workflows) (which contains reusable `workflow_call` workflows, not actions).

## Repository Structure

```text
<action-name>/                    # One directory per action
├── action.yaml                   # Action metadata (name, description, inputs, steps)
└── README.md                     # Per-action docs (template in CONTRIBUTING.md)

.github/
├── workflows/test-<action>.yaml  # One test workflow per action
├── fixtures/                     # Test fixtures consumed by test workflows
└── labels.yaml                   # GitHub issue label definitions

zizmor.yml                        # Action SHA-pinning policy
```

See [README.md](../README.md) for the full list of actions.

## Conventions

All conventions are documented in [CONTRIBUTING.md](../CONTRIBUTING.md). Key rules an agent must follow:

- **Action directory naming:** `<active-verb>-<purpose>` (e.g., `setup-go-toolchain`, not `go-setup`)
- **Inputs/outputs:** kebab-case only (e.g., `app-id`, `github-token`)
- **Action type:** Prefer **composite** over JavaScript/Docker
- **External action pinning:** Pin third-party actions (non-`actions/*`, non-`github/*`, non-`devantler-tech/*`) to commit SHAs with a `# v<version>` comment — enforced by `zizmor.yml`
- **Test workflow required:** Every new action needs `.github/workflows/test-<action-name>.yaml` that uses `step-security/harden-runner` first and `persist-credentials: false` on checkout
- **`action.yaml`:** Always set `author: devantler-tech`

## Adding a New Action

1. Create `<action-name>/action.yaml` and `<action-name>/README.md` (use the README template in CONTRIBUTING.md)
2. Add a row to the Actions table in [README.md](../README.md)
3. Create `.github/workflows/test-<action-name>.yaml` exercising the action
4. Run `zizmor` locally before pushing

## Security & Validation

- [zizmor](https://github.com/zizmorcore/zizmor) scans every workflow on PR
- All workflows must include `step-security/harden-runner` as the first step
- Use semantic commits (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`) — required by the release workflow
