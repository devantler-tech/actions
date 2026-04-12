# Contributing

## Naming Conventions

### Action Directories

Use the `<active-verb>-<purpose>` pattern:

- ✅ `enable-auto-merge-on-pr`, `setup-go-toolchain`, `login-to-ghcr`
- ❌ `auto-merge-action`, `go-setup`, `ghcr`

### Inputs and Outputs

Use **kebab-case** for non-secret inputs, and **UPPER_SNAKE_CASE** for secret inputs:

- ✅ `app-id`, `go-version` (non-secret), `GITHUB_TOKEN`, `APP_PRIVATE_KEY` (secret)
- ❌ `app_id`, `goVersion`, `github-token` (secret in kebab-case)

## Action Structure

Each action directory must contain:

- `action.yaml` — Action metadata with `name`, `description`, `author: devantler-tech`, inputs, and steps
- `README.md` — Documentation following the [template](#readme-template)

### README Template

```markdown
# <Action Name>

<One-line description>

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|

## Outputs

| Name | Description |
|------|-------------|

## Usage

### <Scenario>

\`\`\`yaml
steps:
  - uses: devantler-tech/actions/<action-name>@main
    with:
      ...
\`\`\`
```

## Action Type

Prefer **composite actions** over JavaScript or Docker actions unless complexity demands otherwise.

## Testing

Every action must have a corresponding test workflow at `.github/workflows/test-<action-name>.yaml` that:

1. Triggers on `pull_request` and `push` to `main`
2. Uses `step-security/harden-runner` as the first step
3. Checks out with `persist-credentials: false`
4. Verifies the action works as expected

## Security

- Run [zizmor](https://github.com/zizmorcore/zizmor) to scan for GitHub Actions vulnerabilities
- Pin third-party actions to commit SHAs (enforced by `zizmor.yml`)
- Actions under `actions/*`, `github/*`, and `devantler-tech/*` may use tag-based refs

## Commits

Use [semantic commits](https://www.conventionalcommits.org/):

- `feat:` — New action or feature
- `fix:` — Bug fix
- `docs:` — Documentation changes
- `chore:` — Maintenance tasks
- `ci:` — CI/CD changes
