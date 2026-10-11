# Contributing

## Choose the current owner first

This catalogue is frozen. New integrations, capabilities and ordinary fixes
belong in [devantler-tech/.github](https://github.com/devantler-tech/.github);
start with its [contribution guide](https://github.com/devantler-tech/.github/blob/main/CONTRIBUTING.md).
This repository accepts only urgent fixes for consumers that have not migrated,
each linked to its maintained-catalogue counterpart. Discuss that case in an
[issue](https://github.com/devantler-tech/actions/issues) before changing code.
The legacy conventions below remain reference material, not permission to add
new actions here. Read [AGENTS.md](AGENTS.md) for the canonical contract.

Keep credentials and sensitive findings out of public issues and PRs. Use the
inherited [security policy](https://github.com/devantler-tech/.github/blob/main/.github/SECURITY.md)
for private reporting. No publishing credential or production access is needed
to clarify documentation.

## Check a small documentation correction

For an agreed legacy documentation correction, you need Git, Bash, Mike Farah
`yq` v4, `jq` and standard Unix tools. Fork the repository, replace `YOUR-LOGIN`
below, and start in a new directory:

```sh
git clone https://github.com/YOUR-LOGIN/actions.git
cd actions
git switch -c docs/legacy-reference
```

Clarify an entry-point sentence while preserving the legacy input/secret tables.
From this checkout's root, run the repository's read-only documentation checks:

```sh
bash .scripts/check-workflow-readme.sh
bash .github/tests/test-workflow-readme-parity.sh
git diff --check
```

Success is exit 0, a workflow-parity summary and passing fixture assertions.
These checks parse local YAML/Markdown and use disposable fixture directories;
they do not submit a PR, publish, use secrets or run consumer automation. They
do not prove that a live legacy consumer works. Hosted CI also checks the action
interfaces, workflow wiring, security/pinning and its existing safe fixtures.
Any action/workflow change additionally needs the checks in
[AGENTS.md](AGENTS.md#validation-commands) and its relevant regression tests.

Inspect your diff, stage only intended documentation paths, sign your commit
with `git commit -S`, and push your branch to your own fork. Open a draft PR
against `devantler-tech/actions:main` using the inherited
[PR template](https://github.com/devantler-tech/.github/blob/main/.github/PULL_REQUEST_TEMPLATE.md).
Use a Conventional Commit title, link the issue and maintained counterpart,
record the actual validation and disclose AI assistance if used. Address review
findings; native required CI and current-head substantive review still gate
merge. Do not request GitHub Copilot review.

Follow the inherited [code of conduct](https://github.com/devantler-tech/.github/blob/main/.github/CODE_OF_CONDUCT.md).
Keep existing attribution and third-party licensing intact. There is no root
license file here; do not infer a new licensing grant from this guide.

## Naming Conventions

### Action Directories

For an urgent legacy correction, preserve the existing `<active-verb>-<purpose>` pattern:

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
  - uses: devantler-tech/actions/<action-name>@<full-commit-sha>
    with:
      ...
\`\`\`
```

## Action Type

Prefer **composite actions** over JavaScript or Docker actions unless complexity demands otherwise.

## Distribution and Marketplace

The action suite is portfolio-first and publicly reusable by direct path, but it
is intentionally not published as a family of GitHub Marketplace listings in its
current multi-action repository layout. Marketplace publishing requires a root
`action.yml` or `action.yaml`; metadata in subdirectories is not automatically
listed. Do not add `branding:` to nested action metadata as a proxy for
publication.

If an action develops enough independent demand to justify its own repository,
extract it deliberately and give that single-action repository its own branding,
release lifecycle, and Marketplace listing.

## Testing

Existing actions are tested as `test-<action-name>` jobs inside
`.github/workflows/ci.yaml`, not as separate per-action workflow files. Preserve
their required-check wiring and relevant positive/negative fixtures. Ordinary
step-bearing jobs:

1. Run through CI's declared triggers and change/eligibility conditions
2. Use `step-security/harden-runner` as the first step; the workspace-independent aggregate is the documented exception
3. Check out with `persist-credentials: false`
4. Verify the action works as expected without production side effects

## Security

- Run [zizmor](https://github.com/zizmorcore/zizmor) to scan for GitHub Actions vulnerabilities
- Pin remote actions to full commit SHAs; first-party self-references follow the
  exact-commit checkout/local-path rules in [AGENTS.md](AGENTS.md#self-references-within-this-repo-read-before-referencing-one-part-of-the-repo-from-another).
- Do not copy the floating refs retained in legacy examples or introduce a
  tag-based exception that contradicts the canonical contract.
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

## Reliability

A composite step that performs a **network pull** — a Homebrew tap/install, a
registry login, a tool/toolchain download — can fail a *required* CI check on a
transient registry/network flake (a GHCR 5xx, a DNS/TLS blip) rather than on a
real defect, blocking unrelated PRs across every consumer repo. Wrap such pulls
in the shared bounded-retry helper so infra noise can't masquerade as a failure:

```bash
retry() { bash "${GITHUB_ACTION_PATH}/../.scripts/retry.sh" "$@"; }
retry brew install <formula>
```

`.scripts/retry.sh` retries with exponential backoff (tunable via
`RETRY_MAX_ATTEMPTS`, `RETRY_BASE_DELAY`, `RETRY_MAX_DELAY`) and exits non-zero
with the command's last status once attempts are exhausted, so a genuine failure
still reds the check. Only wrap the **network** commands — leave local operations
unwrapped. It is used by `setup-ksail-cli` (`brew tap` / `brew install`), by the
shared `.scripts/ensure-gh-skill.sh` (the `gh` release download), and by
`setup-agent-skills` / `update-agent-skills` (`gh skill install` / `gh skill
update` registry pulls) — covering every shell-based network pull in the suite as
part of the reliability pillar
([#247](https://github.com/devantler-tech/actions/issues/247)).

## Commits

Use [semantic commits](https://www.conventionalcommits.org/):

- `feat:` — New action or feature
- `fix:` — Bug fix
- `docs:` — Documentation changes
- `chore:` — Maintenance tasks
- `ci:` — CI/CD changes
