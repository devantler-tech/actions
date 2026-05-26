# Upload Coverage

Upload a Cobertura XML coverage report to [GitHub Code Quality](https://docs.github.com/code-security/code-quality) so the aggregate coverage percentage appears on pull requests.

GitHub Code Quality requires the org/repo to be on a **Team** or **Enterprise Cloud** plan, and **Code Quality must be enabled** in the repository's _Settings → Code quality_. Fork PRs and merge-queue runs are skipped automatically by the underlying [`actions/upload-code-coverage`](https://github.com/actions/upload-code-coverage) action.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `file` | Path to the Cobertura XML coverage report to upload | ✅ | - |
| `language` | Linguist language name for the report (e.g. `Go`, `C#`) | ✅ | - |
| `label` | Label for the coverage report (e.g. `code-coverage/go`) | ❌ | `code-coverage` |
| `fail-on-error` | Fail the step if the GitHub upload fails (errors are always surfaced as annotations) | ❌ | `false` |
| `token` | GitHub token with `code-quality: write` (the calling job must grant the permission) | ❌ | `${{ github.token }}` |

## Outputs

This action has no outputs.

## Permissions

The **calling job** must grant `code-quality: write` — a composite action cannot declare it. For push-triggered workflows that resolve PR numbers, also add `pull-requests: read`.

```yaml
permissions:
  contents: read
  code-quality: write
```

## Usage

### Go (Cobertura produced via gocover-cobertura)

```yaml
permissions:
  contents: read
  code-quality: write
steps:
  - name: 📄 Generate coverage
    run: |
      go test -race -coverprofile=coverage.txt -covermode=atomic ./...
      go run github.com/boumenot/gocover-cobertura@latest < coverage.txt > coverage.cobertura.xml

  - name: 📊 Upload coverage
    uses: devantler-tech/actions/upload-coverage@main
    with:
      file: coverage.cobertura.xml
      language: Go
      label: code-coverage/go
```

### .NET (Cobertura produced by `dotnet test --collect:"XPlat Code Coverage"`)

```yaml
permissions:
  contents: read
  code-quality: write
steps:
  - name: 📊 Upload coverage
    uses: devantler-tech/actions/upload-coverage@main
    with:
      file: ./TestResults/coverage.cobertura.xml
      language: C#
      label: code-coverage/dotnet
```
