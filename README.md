# DevantlerTech GitHub Actions & Reusable Workflows 🚀

The shared CI/CD building blocks used across all DevantlerTech projects — both **composite actions** and **reusable `workflow_call` workflows** — in one repository. (The reusable workflows were merged in from `devantler-tech/reusable-workflows`; that repo is being retired and will be archived once all consumers migrate their `uses:` pins here.)

The diagram below shows how GitHub Workflows, Jobs, Steps, Reusable Workflows, and Actions relate.

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
  D --> E[Actions]
  E -.- F([Composite Actions])
  F --> D
  E -.- G([JavaScript Actions])
  E -.- H([Docker Container Actions])
```

## Actions

| Action | Description |
|--------|-------------|
| [aggregate-job-checks](aggregate-job-checks/README.md) | Aggregate multiple job results into a single required check |
| [approve-pr](approve-pr/README.md) | Approve a PR using a GitHub App identity |
| [cleanup-ghcr-packages](cleanup-ghcr-packages/README.md) | Clean up old GHCR packages |
| [create-issues-from-todos](create-issues-from-todos/README.md) | Create GitHub issues from TODO comments |
| [dependency-review](dependency-review/README.md) | Scan a PR's dependency changes for vulnerabilities and disallowed licenses |
| [diagnose-flux](diagnose-flux/README.md) | Dump Flux reconcile state, controller logs, and failing pod logs on a stuck deploy |
| [enable-auto-merge-on-pr](enable-auto-merge-on-pr/README.md) | Enable auto-merge on a pull request |
| [free-disk-space](free-disk-space/README.md) | Reclaim runner disk by removing large preinstalled toolchains |
| [login-to-ghcr](login-to-ghcr/README.md) | Login to GitHub Container Registry |
| [run-dotnet-tests](run-dotnet-tests/README.md) | Test .NET solution or project with coverage |
| [setup-agent-skills](setup-agent-skills/README.md) | Install agent skills via `gh skill` from a newline list of `<owner/repo> <skill>[@pin]` entries, for one or more agents (e.g. Copilot, Claude Code) |
| [setup-go-toolchain](setup-go-toolchain/README.md) | Setup Go with optional private module support |
| [setup-ksail-cli](setup-ksail-cli/README.md) | Install KSail CLI via Homebrew |
| [update-agent-skills](update-agent-skills/README.md) | Run `gh skill update --all` against installed skills and report changes |
| [upload-coverage](upload-coverage/README.md) | Upload a Cobertura coverage report to GitHub Code Quality |
| [upsert-issue](upsert-issue/README.md) | Create, update, reopen, or close a GitHub issue by title |

### Distribution

This repository is a portfolio-first, publicly reusable catalogue. Consumers call
an action directly as `devantler-tech/actions/<action-name>@<ref>`; the suite is
intentionally not published as a family of GitHub Marketplace listings in its
current multi-action layout.

[GitHub Marketplace publishing requires a root action metadata file](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace),
and action metadata in subdirectories is not automatically listed. This repository
instead contains multiple subdirectory actions and reusable workflows under one
release stream, so adding `branding:` to the nested `action.yaml` files would not
make them independently discoverable and is deliberately omitted.

Revisit Marketplace publication only when an action has enough independent demand
to justify extraction into its own single-action repository. That repository should
then carry its own branding and Marketplace release lifecycle.

## Reusable Workflows

[Reusable workflows](https://docs.github.com/en/actions/how-tos/sharing-automations/reuse-workflows#creating-a-reusable-workflow) are designed to encapsulate common CI/CD patterns that can be shared across multiple repositories. They allow you to define a workflow once and reuse it in the job-scope of other workflows. This reduces duplication and enables building generic workflows for common tasks.

### 🎉 Create Release

<details>
<summary>Click to expand</summary>

[.github/workflows/create-release.yaml](.github/workflows/create-release.yaml) is a workflow used to create releases using semantic-release.

The release is published with a GitHub App token, so the caller must set the `APP_CLIENT_ID` repository/organization **variable** alongside the `APP_PRIVATE_KEY` **secret**. The App needs `contents: write` (tags/releases) and `issues: write` + `pull-requests: write` (release comments).

#### Usage

```yaml
jobs:
  release:
    uses: devantler-tech/actions/.github/workflows/create-release.yaml@{ref} # ref
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

#### Secrets and Inputs

| Key               | Type            | Default | Required | Description                                                       |
|-------------------|-----------------|---------|----------|-------------------------------------------------------------------|
| `APP_CLIENT_ID`   | Variable        | -       | Yes      | GitHub App client ID used to mint the release token               |
| `APP_PRIVATE_KEY` | Secret          | -       | Yes      | GitHub App private key (paired with the `APP_CLIENT_ID` variable) |
| `dry-run`         | Input (boolean) | `false` | No       | Run semantic-release in dry-run mode (no tags or publishes)       |

</details>

### 🗑️ Delete Workflow Runs

<details>
<summary>Click to expand</summary>

[.github/workflows/delete-workflow-runs.yaml](.github/workflows/delete-workflow-runs.yaml) is a workflow used to clean up old workflow runs from a repository.

#### Usage

```yaml
jobs:
  delete-runs:
    uses: devantler-tech/actions/.github/workflows/delete-workflow-runs.yaml@{ref} # ref
    permissions:
      actions: write
      contents: read
    with:
      days: 30 # optional
      minimum-runs: 6 # optional
      dry-run: false # required to perform actual deletions (defaults to true)
```

#### Secrets and Inputs

| Key                                | Type            | Default      | Required | Description                                        |
|------------------------------------|-----------------|--------------|----------|----------------------------------------------------|
| `repository`                       | Input (string)  | Calling repo | No       | Repository to target for workflow run deletion     |
| `days`                             | Input (number)  | `30`         | No       | Days-worth of runs to keep for each workflow       |
| `minimum-runs`                     | Input (number)  | `6`          | No       | Minimum runs to keep for each workflow             |
| `delete-workflow-pattern`          | Input (string)  | -            | No       | Name or filename of the workflow to target         |
| `delete-workflow-by-state-pattern` | Input (string)  | `ALL`        | No       | Filter workflows by state (comma-separated)        |
| `delete-run-by-conclusion-pattern` | Input (string)  | `ALL`        | No       | Remove runs based on conclusion (comma-separated)  |
| `dry-run`                          | Input (boolean) | `true`       | No       | Logs simulated changes, no deletions are performed |

> **Note:** The calling workflow must grant `actions: write` and `contents: read` permissions.

</details>

### 🛡️ Dependency Review

<details>
<summary>Click to expand</summary>

[.github/workflows/dependency-review.yaml](.github/workflows/dependency-review.yaml) scans a pull request's dependency changes for known-vulnerable packages and disallowed licenses using [GitHub Dependency Review](https://github.com/actions/dependency-review-action). It is designed to run as an organization **Required Workflow** as well as via `workflow_call`.

It is **non-blocking by default** (`warn-only: true`, `fail-on-severity: critical`) so it can be required org-wide without blocking existing PRs; set `warn-only: false` to enforce. With `comment-summary-in-pr: never` (the default) the job needs only `contents: read`.

#### Usage

```yaml
jobs:
  dependency-review:
    uses: devantler-tech/actions/.github/workflows/dependency-review.yaml@{ref} # ref
```

#### Inputs

| Name | Description | Default |
|------|-------------|---------|
| `fail-on-severity` | Block on vulnerabilities of this severity or higher (`low`, `moderate`, `high`, `critical`); only when `warn-only` is false. | `critical` |
| `fail-on-scopes` | Comma-separated scopes to block on (`runtime`, `development`, `unknown`). | `runtime` |
| `allow-licenses` | Comma-separated SPDX allow-list (empty = not enforced). Mutually exclusive with `deny-licenses`. | `""` |
| `deny-licenses` | Comma-separated SPDX deny-list (empty = not enforced). Mutually exclusive with `allow-licenses`. | `""` |
| `comment-summary-in-pr` | Post the summary as a PR comment (`always`, `on-failure`, `never`); anything but `never` needs `pull-requests: write`. | `never` |
| `warn-only` | Report findings as warnings and always succeed (non-blocking); set `false` to enforce. | `true` |

</details>

### 🚀 Deploy GitHub Pages

<details>
<summary>Click to expand</summary>

[.github/workflows/deploy-github-pages.yaml](.github/workflows/deploy-github-pages.yaml) is a workflow used to build and deploy a Jekyll site to GitHub Pages.

#### Usage

```yaml
jobs:
  pages:
    uses: devantler-tech/actions/.github/workflows/deploy-github-pages.yaml@{ref} # ref
    with:
      ruby-version: "3.3" # optional
      jekyll-env: production # optional
      extra-build-args: "" # optional, e.g. '--future'
      working-directory: "." # optional, e.g. 'docs' if Jekyll site is in a subdirectory
```

#### Secrets and Inputs

| Key                 | Type            | Default      | Required | Description                                                     |
|---------------------|-----------------|--------------|----------|-----------------------------------------------------------------|
| `dry-run`           | Input (boolean) | `false`      | No       | Skip build and deploy (validate workflow interface only)        |
| `ruby-version`      | Input (string)  | `3.3`        | No       | Ruby version to install                                         |
| `jekyll-env`        | Input (string)  | `production` | No       | Jekyll environment                                              |
| `extra-build-args`  | Input (string)  | `""`         | No       | Extra args appended before the automatically supplied --baseurl |
| `working-directory` | Input (string)  | `"."`        | No       | Working directory for the Jekyll site (e.g., 'docs')            |

#### Outputs

| Key        | Description             |
|------------|-------------------------|
| `page-url` | Deployed Pages site URL |

</details>

### 🔀 Enable Auto-Merge

<details>
<summary>Click to expand</summary>

[.github/workflows/enable-auto-merge.yaml](.github/workflows/enable-auto-merge.yaml) is a workflow that approves and enables auto-merge on pull requests from an exact-match allowlist of trusted single-author bots. It carries an **opt-in, default-off** fail-closed review/pre-merge gate (`.scripts/check-merge-gates.sh`, enabled via the `enforce-review-gates` input or the `ENFORCE_MERGE_GATES` repository/organization variable): when enforced, approval and arming require, at the PR's **current head**, a green review (CodeRabbit's **latest** head verdict `APPROVED`, or a Codex clean pass when CodeRabbit has no head verdict) and a green, **fresh** CodeRabbit pre-merge result (the summary's last update must not predate the head commit; a `⚠️`/`❌`/`❓` mark in either summary shape fails it) — and a gate that turns red later actively **disarms** a previously armed PR. Missing, stale, mixed, or unparseable state skips arming (the portfolio's maintenance agent arms such PRs after its own live checks). The gate script is checked out from the **workflow-defining** repository at the running commit (`job.workflow_repository`/`job.workflow_sha`), and both the approval (`commit_id`) and the arming (`--match-head-commit`) bind to the gate-proven head so a racing push invalidates them. Because review results land after the `pull_request` events, the workflow also triggers on `pull_request_review`/`issue_comment` where it lives; `workflow_call` consumers that enable enforcement must add those triggers to their **caller** workflow (a reusable workflow cannot schedule its callers).

#### Usage

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  # Required when enforce-review-gates is true: review results land after
  # the pull_request events, so the caller must re-invoke the gate on them
  # — including dismissals, which are non-green and must be able to DISARM.
  pull_request_review:
    types: [submitted, dismissed]
  issue_comment:
    types: [created, edited]

jobs:
  auto-merge:
    uses: devantler-tech/actions/.github/workflows/enable-auto-merge.yaml@{ref} # ref
    permissions:
      pull-requests: write
      contents: write
      # The gate's read-only lookups run on GITHUB_TOKEN, not the App token:
      checks: read
      actions: read
    with:
      enforce-review-gates: false # default; flip after the repo's review lanes are validated
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

#### Secrets and Inputs

| Key                    | Type   | Default | Required | Description                                                        |
|------------------------|--------|---------|----------|--------------------------------------------------------------------|
| `APP_PRIVATE_KEY`      | Secret | -       | Yes      | GitHub App private key                                             |
| `enforce-review-gates` | Input  | `false` | No       | Opt-in fail-closed review/pre-merge gate before approving/arming   |

</details>

### 📦 Publish App

<details>
<summary>Click to expand</summary>

[.github/workflows/publish-app.yaml](.github/workflows/publish-app.yaml) is a workflow used to build and publish a containerized app and its Kubernetes manifests to GHCR as cosign-signed OCI artifacts. It builds and pushes the container image (tagged with the semantic version derived from the git tag — e.g. `1.2.3` from a `v1.2.3` tag — plus `sha-<sha>` and `latest`), pins the built image digest into the deployment manifest's `app-name` container, pushes the manifests directory as a Flux-compatible OCI artifact (`ghcr.io/<owner>/<repo>/manifests`), and signs both the image and the manifests artifact with keyless cosign (Fulcio/Rekor via GitHub OIDC).

#### Usage

```yaml
on:
  push:
    tags:
      - "v*"

jobs:
  publish-app:
    uses: devantler-tech/actions/.github/workflows/publish-app.yaml@{ref} # ref
    permissions:
      contents: read # checkout
      packages: write # push image + manifests OCI artifact
      id-token: write # keyless cosign signing
    with:
      app-name: my-app # container name in deploy/deployment.yaml
      deploy-path: ./deploy # optional
```

> **Note:** Must be invoked from a semver tag (`vX.Y.Z`) — Docker semver tagging and Flux `OCIRepository` semver selection depend on it. The calling job must grant `packages: write` and `id-token: write` (and `contents: read` for checkout); no secrets are required (auth uses the GHCR-scoped `GITHUB_TOKEN`).

#### Secrets and Inputs

| Key           | Type           | Default    | Required | Description                                                                |
|---------------|----------------|------------|----------|----------------------------------------------------------------------------|
| `app-name`    | Input (string) | -          | Yes      | Container name in the deployment manifest to pin to the built image digest |
| `deploy-path` | Input (string) | `./deploy` | No       | Path to the Kubernetes manifests directory packaged as the OCI artifact    |

</details>

### 📦 Publish Manifests

<details>
<summary>Click to expand</summary>

[.github/workflows/publish-manifests.yaml](.github/workflows/publish-manifests.yaml) is a workflow used to publish a Kubernetes manifests directory to GHCR as a cosign-signed OCI artifact — **with no container image build**. Use it for repos that ship only manifests (e.g. GitOps/Crossplane desired-state) rather than an application: it pushes the manifests directory as a Flux-compatible OCI artifact (`ghcr.io/<owner>/<repo>/manifests`, tagged with the semantic version derived from the git tag — e.g. `1.2.3` from a `v1.2.3` tag — plus `latest`), then signs the artifact by digest with keyless cosign (Fulcio/Rekor via GitHub OIDC). It is the manifests-only sibling of `publish-app.yaml` (which additionally builds and signs a container image).

Because the signing happens inside this reusable workflow, the cosign certificate identity (OIDC `subject`) is this workflow's path — `https://github.com/devantler-tech/actions/.github/workflows/publish-manifests.yaml@<ref>` — not the caller's. Verifiers (e.g. a Flux `OCIRepository` `verify.matchOIDCIdentity`) must match that.

#### Usage

```yaml
on:
  push:
    tags:
      - "v*"

jobs:
  publish-manifests:
    uses: devantler-tech/actions/.github/workflows/publish-manifests.yaml@{ref} # ref
    permissions:
      contents: read # checkout
      packages: write # push manifests OCI artifact
      id-token: write # keyless cosign signing
    with:
      oci-name: devantler-tech/github-config # optional override; defaults to github.repository
      deploy-path: ./deploy # optional
```

> **Note:** Must be invoked from a semver tag (`vX.Y.Z`) — Flux `OCIRepository` semver selection depends on it. The calling job must grant `packages: write` and `id-token: write` (and `contents: read` for checkout); no secrets are required (auth uses the GHCR-scoped `GITHUB_TOKEN`). Override `oci-name` when the repo name is an invalid OCI path component (e.g. `.github` → `devantler-tech/github-config`).

#### Secrets and Inputs

| Key           | Type           | Default              | Required | Description                                                                                                                            |
|---------------|----------------|----------------------|----------|--------------------------------------------------------------------------------------------------------------------------------------|
| `oci-name`    | Input (string) | `${{ github.repository }}` | No       | OCI repository name (`<owner>/<name>`) the artifact is published under, without the registry prefix or trailing `/manifests`. Override for invalid OCI path components |
| `deploy-path` | Input (string) | `./deploy`           | No       | Path to the Kubernetes manifests directory packaged as the OCI artifact                                                              |

</details>

### 📦 Publish .NET Library

<details>
<summary>Click to expand</summary>

[.github/workflows/publish-dotnet-library.yaml](.github/workflows/publish-dotnet-library.yaml) is a workflow used to publish .NET libraries to NuGet and GHCR.

#### Usage

```yaml
jobs:
  publish-library:
    uses: devantler-tech/actions/.github/workflows/publish-dotnet-library.yaml@{ref} # ref
    secrets:
      NUGET_API_KEY: ${{ secrets.NUGET_API_KEY }}
```

#### Secrets and Inputs

| Key             | Type            | Default | Required | Description                                          |
|-----------------|-----------------|---------|----------|------------------------------------------------------|
| `NUGET_API_KEY` | Secret          | -       | No       | NuGet API key (required when `dry-run` is `false`)   |
| `dry-run`       | Input (boolean) | `false` | No       | Skip publish (validate workflow interface only)      |

</details>

### 🧪 Run .NET Tests

<details>
<summary>Click to expand</summary>

[.github/workflows/run-dotnet-tests.yaml](.github/workflows/run-dotnet-tests.yaml) is a workflow used to test .NET solutions or projects across multiple operating systems. Coverage is merged into a single Cobertura report and uploaded to **GitHub Code Quality** (native PR coverage).

#### Usage

```yaml
jobs:
  dotnet-test:
    uses: devantler-tech/actions/.github/workflows/run-dotnet-tests.yaml@{ref} # ref
    permissions:
      contents: read
      packages: read
      code-quality: write # required for GitHub Code Quality coverage upload
```

> **Note:** The calling workflow must grant `code-quality: write` (otherwise the run fails at startup). Coverage requires the repo's **Code Quality** to be enabled (_Settings → Code quality_).

#### Secrets and Inputs

This workflow needs no caller-provided secrets or inputs — it authenticates to the GHCR NuGet feed with the automatic `GITHUB_TOKEN` (requires the `packages: read` permission shown above).

</details>

### 📝 Scan for TODO Comments

<details>
<summary>Click to expand</summary>

[.github/workflows/scan-for-todo-comments.yaml](.github/workflows/scan-for-todo-comments.yaml) is a workflow used to scan for TODOs in code and create GitHub issues.

#### Usage

```yaml
jobs:
  todos:
    uses: devantler-tech/actions/.github/workflows/scan-for-todo-comments.yaml@{ref} # ref
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

#### Secrets and Inputs

| Key               | Type            | Default | Required | Description                                                |
|-------------------|-----------------|---------|----------|------------------------------------------------------------|
| `APP_CLIENT_ID`   | Variable        | -       | Yes      | GitHub App client ID used to mint the issue-creation token |
| `APP_PRIVATE_KEY` | Secret          | -       | Yes      | GitHub App private key (paired with the `APP_CLIENT_ID` variable) |
| `dry-run`         | Input (boolean) | `false` | No       | Skip issue creation (validate workflow interface only)     |

</details>

### 🔍 Scan for Workflow Vulnerabilities

<details>
<summary>Click to expand</summary>

[.github/workflows/scan-for-workflow-vulnerabilities.yaml](.github/workflows/scan-for-workflow-vulnerabilities.yaml) is a workflow used to perform static analysis on GitHub Actions workflows using [Zizmor](https://github.com/zizmorcore/zizmor).

#### Usage

```yaml
jobs:
  zizmor:
    uses: devantler-tech/actions/.github/workflows/scan-for-workflow-vulnerabilities.yaml@{ref} # ref
```

</details>

### 🔄 Sync Cluster Policies

<details>
<summary>Click to expand</summary>

[.github/workflows/sync-cluster-policies.yaml](.github/workflows/sync-cluster-policies.yaml) is a workflow used to sync upstream Kyverno policies to a target directory.

Which policies are synced is controlled by a `.policyignore` file at the repo root. It uses gitignore-style syntax — ordered glob patterns, one per line, where a leading `!` re-includes a previously excluded path — so you can exclude everything by default and whitelist just the policies you want:

```gitignore
# Ignore every category…
other*
# …except these two policies.
!other/create-pod-antiaffinity/create-pod-antiaffinity.yaml
!other/spread-pods-across-topology/spread-pods-across-topology.yaml
```

Patterns are evaluated per file with last-match-wins, so a `!` re-include still applies even when a broad earlier pattern matched its parent directory.

#### Usage

```yaml
jobs:
  sync-cluster-policies:
    uses: devantler-tech/actions/.github/workflows/sync-cluster-policies.yaml@{ref} # ref
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
    with:
      kyverno-policies-dir: policies/kyverno
```

#### Secrets and Inputs

| Key                    | Type            | Default | Required | Description                                              |
|------------------------|-----------------|---------|----------|----------------------------------------------------------|
| `APP_PRIVATE_KEY`      | Secret          | -       | Yes      | GitHub App private key                                   |
| `kyverno-policies-dir` | Input (string)  | -       | Yes      | Directory to sync Kyverno policies to                    |
| `dry-run`              | Input (boolean) | `false` | No       | Skip sync and PR creation (validate workflow interface only) |

</details>

### 🔄 Template Sync

<details>
<summary>Click to expand</summary>

[.github/workflows/template-sync.yaml](.github/workflows/template-sync.yaml) keeps a repository in sync with an upstream template repository via [AndreasAugustin/actions-template-sync](https://github.com/AndreasAugustin/actions-template-sync), opening a PR with any incoming template changes. List the files this repository *owns* (and that must never be overwritten by the template) in a `.templatesyncignore` file at the repo root — everything else the template ships is kept in sync.

#### Usage

```yaml
on:
  schedule:
    - cron: "0 6 * * 1"
  workflow_dispatch:

jobs:
  template-sync:
    uses: devantler-tech/actions/.github/workflows/template-sync.yaml@{ref} # ref
    with:
      source-repo-path: devantler-tech/gitops-tenant-template
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
```

By default the sync PR is opened with a GitHub App token (`use-app-token: true`) so it triggers the caller's CI; this needs the `APP_CLIENT_ID` variable and the `APP_PRIVATE_KEY` secret. Set `use-app-token: false` to fall back to `GITHUB_TOKEN` (the PR then will not trigger `on: pull_request` checks).

#### Secrets and Inputs

| Key                              | Type            | Default                                          | Required | Description                                                                 |
|----------------------------------|-----------------|--------------------------------------------------|----------|-----------------------------------------------------------------------------|
| `APP_PRIVATE_KEY`                | Secret          | -                                                | When `use-app-token` | GitHub App private key (paired with the `APP_CLIENT_ID` variable) |
| `source-repo-path`               | Input (string)  | -                                                | Yes      | `owner/repo` of the upstream template to sync from                          |
| `upstream-branch`                | Input (string)  | `main`                                           | No       | Branch of the template repository to sync from                              |
| `pr-title`                       | Input (string)  | `chore: sync changes from the upstream template` | No       | Title of the sync PR (Conventional-Commit by default)                       |
| `pr-commit-msg`                  | Input (string)  | `chore: sync changes from the upstream template` | No       | Commit message for the sync PR                                              |
| `pr-labels`                      | Input (string)  | `dependencies,automation`                        | No       | Comma-separated labels for the sync PR                                      |
| `pr-branch-name-prefix`          | Input (string)  | `chore/template-sync`                            | No       | Prefix for the branch the sync PR is opened from                            |
| `template-sync-ignore-file-path` | Input (string)  | `.templatesyncignore`                            | No       | Path to the file listing consumer-owned (non-synced) files                  |
| `use-app-token`                  | Input (boolean) | `true`                                           | No       | Open the sync PR with a GitHub App token so it triggers the caller's CI     |
| `dry-run`                        | Input (boolean) | `false`                                          | No       | Skip the sync and PR creation (validate workflow interface only)            |

> **Note:** The calling workflow runs the sync job with `contents: write` and `pull-requests: write` (declared by the reusable workflow).

</details>

### 🔄 Update Agent Skills

<details>
<summary>Click to expand</summary>

[.github/workflows/update-agent-skills.yaml](.github/workflows/update-agent-skills.yaml) is a workflow used to keep installed agent skills (Copilot, Claude Code, …) up-to-date via [`gh skill update --all`](https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/), opening a PR with any changes. Each installed `SKILL.md`'s `metadata.github-*` frontmatter is the source of truth — no lockfile is required. Works with any mix of `gh skill`-compatible upstreams.

#### Usage

```yaml
on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch:

jobs:
  update-agent-skills:
    uses: devantler-tech/actions/.github/workflows/update-agent-skills.yaml@{ref} # ref
    permissions:
      contents: write
      pull-requests: write
    with:
      dir: .agents/skills
```

The workflow assumes skills were previously installed with [`devantler-tech/actions/setup-agent-skills`](https://github.com/devantler-tech/actions/tree/main/setup-agent-skills) (or `gh skill install` directly) — the committed `SKILL.md` files carry the upstream pointers.

#### Secrets and Inputs

| Key              | Type            | Default                              | Required | Description                                                            |
|------------------|-----------------|--------------------------------------|----------|------------------------------------------------------------------------|
| `dir`            | Input (string)  | `.`                                  | No       | Directory to scan for installed skills (passed to `gh skill update --dir`) |
| `unpin`          | Input (boolean) | `false`                              | No       | When `true`, pass `--unpin` (clear pinned versions)                    |
| `gh-version`     | Input (string)  | `2.90.0`                             | No       | Minimum required `gh` version (must support `gh skill`)                |
| `pr-branch`      | Input (string)  | `deps/agent-skills-update`           | No       | Branch the update PR is opened from                                    |
| `pr-title`       | Input (string)  | `chore(deps): update agent skills`   | No       | Title of the update PR                                                 |
| `pr-labels`      | Input (string)  | `dependencies,automation`            | No       | Comma-separated labels for the update PR                               |
| `commit-message` | Input (string)  | `chore(deps): update agent skills`   | No       | Commit message for the update PR                                       |
| `dry-run`        | Input (boolean) | `false`                              | No       | Skip update and PR creation (validate workflow interface only)         |

> **Note:** The calling workflow must grant `contents: write` and `pull-requests: write` permissions.

</details>

### ✅ Validate Go Project

<details>
<summary>Click to expand</summary>

[.github/workflows/validate-go-project.yaml](.github/workflows/validate-go-project.yaml) is a workflow used to lint and test Go projects across multiple operating systems.

#### Features

- **Automated Linting**: Runs `golangci-lint` and `mega-linter` to ensure code quality
- **Auto-fix**: Automatically applies linter fixes and commits them
- **Copilot Integration**: When linting fails, automatically prompts Copilot on the PR to fix the remaining issues
- **Supply-chain Scanning**: Runs [`govulncheck`](https://go.dev/blog/govulncheck) via the official [`golang/govulncheck-action`](https://github.com/golang/govulncheck-action) to fail the PR on known vulnerabilities your code actually calls (call-graph reachability, so imported-but-unreachable advisories don't block). A consumer can risk-accept a reachable advisory that has no upstream fix (`Fixed in: N/A`) by committing an optional `.govulncheck-allow.txt` at the repo root (one `GO-YYYY-NNNN  # justification` per line; `#` comments and blank lines ignored); the gate stays strict for everything else. Repos with no allowlist file keep using the official action unchanged — only opt-in repos take the allowlist-aware path.
- **Code Coverage**: Generates a Cobertura report and uploads it to **GitHub Code Quality** (native PR coverage).

#### Usage

```yaml
jobs:
  go-test:
    uses: devantler-tech/actions/.github/workflows/validate-go-project.yaml@{ref} # ref
    permissions:
      contents: write
      code-quality: write # required for GitHub Code Quality coverage upload
    secrets:
      APP_PRIVATE_KEY: ${{ secrets.APP_PRIVATE_KEY }}
    with:
      pr-owner: ${{ github.event.pull_request.user.login }} # optional
```

> **Note:** The calling workflow must grant `code-quality: write` so coverage can be uploaded to GitHub Code Quality. Coverage requires the repo's **Code Quality** to be enabled (_Settings → Code quality_).

#### Secrets and Inputs

| Key               | Type           | Default | Required | Description                                                         |
|-------------------|----------------|---------|----------|---------------------------------------------------------------------|
| `APP_PRIVATE_KEY` | Secret         | -       | No       | GitHub App private key for authenticating the workflow              |
| `pr-owner`        | Input (string) | -       | No       | Pull request author login (used to disable auto-commit for bot PRs) |

</details>

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions and guidelines.
