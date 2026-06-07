# Contributing

## Naming Conventions

### Action Directories

Use the `<active-verb>-<purpose>` pattern:

- ✅ `enable-auto-merge-on-pr`, `setup-go-toolchain`, `login-to-ghcr`
- ❌ `auto-merge-action`, `go-setup`, `ghcr`

### Inputs and Outputs

Use **kebab-case** for all action inputs, including secret-backed ones. Workflow inputs can keep their own conventions:

- ✅ `app-id`, `go-version`, `github-token`, `app-private-key`
- ❌ `app_id`, `goVersion`, `GITHUB_TOKEN`, `APP_PRIVATE_KEY`

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
- **External action pin comment convention.** Annotate each third-party SHA pin so a
  reader can tell at a glance whether it tracks a tag or a branch:
  - Pinned to a release tag → `# v<version>` (e.g. `# v6.0.2`). This is the default;
    12/13 third-party pins use it.
  - Pinned to a branch commit because the upstream publishes **no tags or releases**
    (main-tracked only) → `# <branch> (no upstream releases)` (e.g.
    `# main (no upstream releases)`). This keeps the comment honest — it names the
    branch and *why* there is no version — so a future re-pin to a newer branch
    commit isn't mistaken for a floating `@main` ref. The lone such dep today is
    `Homebrew/actions/setup-homebrew` in `setup-ksail-cli`.

## Commits

Use [semantic commits](https://www.conventionalcommits.org/):

- `feat:` — New action or feature
- `fix:` — Bug fix
- `docs:` — Documentation changes
- `chore:` — Maintenance tasks
- `ci:` — CI/CD changes
