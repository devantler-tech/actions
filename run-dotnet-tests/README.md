# Run Dotnet Tests

Test .NET solutions or projects across multiple platforms with code coverage reporting. Sets up the .NET 9 SDK, configures NuGet sources (including GHCR for private packages), runs tests with coverage collection, and uploads reports to Codecov.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `app-id` | GitHub App ID to generate a token | ✅ | - |
| `app-private-key` | Private key of the GitHub App | ✅ | - |
| `github-token` | GitHub token to access the repository | ✅ | - |
| `codecov-token` | Token to upload code coverage to CodeCov | ❌ | - |
| `working-directory` | Directory to run the tests in | ❌ | `.` |

## Usage

### With code coverage

```yaml
steps:
  - name: Test .NET project
    uses: devantler-tech/actions/run-dotnet-tests@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
      codecov-token: ${{ secrets.CODECOV_TOKEN }}
```

### Custom working directory

```yaml
steps:
  - name: Test .NET project
    uses: devantler-tech/actions/run-dotnet-tests@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
      working-directory: src/MyProject
```

### Without code coverage

```yaml
steps:
  - name: Test .NET project
    uses: devantler-tech/actions/run-dotnet-tests@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
```
