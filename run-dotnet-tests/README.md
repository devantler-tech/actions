# Run Dotnet Tests

Test .NET solutions or projects across multiple platforms with code coverage reporting. Sets up the .NET 9 (STS) and .NET 10 (LTS) SDKs side-by-side, optionally configures GHCR for private packages, runs tests with coverage collection, and uploads the report to **GitHub Code Quality** (native PR coverage) on authenticated runs.

> **Permissions:** the calling job must grant `code-quality: write` for the GitHub Code Quality upload. The coverage is merged into a single Cobertura report (via ReportGenerator) and uploaded once, from the Linux matrix leg only. The upload is best-effort (it never fails the build), requires the repo's **Code Quality** to be enabled (_Settings → Code quality_), and is skipped when `github-token` is empty.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `github-token` | GitHub token for authenticated GHCR package restore and Code Quality upload. Omit it when testing untrusted pull-request code. | ❌ | `""` |
| `working-directory` | Directory to run the tests in | ❌ | `.` |

## Usage

### Basic

```yaml
steps:
  - name: Test .NET project
    uses: devantler-tech/actions/run-dotnet-tests@main
```

### Custom working directory

```yaml
steps:
  - name: Test .NET project
    uses: devantler-tech/actions/run-dotnet-tests@main
    with:
      working-directory: src/MyProject
```

Pass `github-token` only for trusted runs that need to restore private packages from
GitHub Packages. The reusable workflow intentionally omits it on `pull_request` events so
PR-controlled MSBuild targets and tests cannot read the credential. Credential-free runs
also skip the token-bearing GitHub Code Quality upload.

## Reusable workflow

The reusable workflow is credential-free on pull requests by default. Trusted same-repository
human-authored pull requests that need private GitHub Packages can opt in explicitly:

```yaml
jobs:
  test:
    uses: devantler-tech/actions/.github/workflows/run-dotnet-tests.yaml@main
    with:
      enable-github-packages: true
    permissions:
      contents: read
      packages: read
      code-quality: write
```

The workflow honors `enable-github-packages` only when the pull request head is in the
same repository and the pull request author is not a bot. Fork and bot pull requests remain
credential-free even if they set the input. Merge-group and direct non-pull-request runs
retain authenticated restore and Code Quality upload without the opt-in.
