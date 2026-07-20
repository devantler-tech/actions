# Run Dotnet Tests

Test .NET solutions or projects across multiple platforms with code coverage reporting. Sets up the .NET 9 (STS) and .NET 10 (LTS) SDKs side-by-side, optionally configures GHCR for private packages, runs tests with coverage collection, and uploads the report to **GitHub Code Quality** (native PR coverage).

> **Permissions:** the calling job must grant `code-quality: write` for the GitHub Code Quality upload. The coverage is merged into a single Cobertura report (via ReportGenerator) and uploaded once, from the Linux matrix leg only. The upload is best-effort (it never fails the build) and requires the repo's **Code Quality** to be enabled (_Settings → Code quality_).

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `github-token` | GitHub token for authenticated GHCR package restore. Omit it when testing untrusted pull-request code. | ❌ | `""` |
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
PR-controlled MSBuild targets and tests cannot read the credential.
