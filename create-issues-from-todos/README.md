# Create Issues from TODOs

Scan code for TODO comments and automatically create corresponding GitHub issues. Authenticates via GitHub App, locates TODOs with file and line references, and can optionally add issues to a GitHub Project.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `app-id` | GitHub App ID | ✅ | - |
| `app-private-key` | GitHub App Private Key | ✅ | - |
| `project` | GitHub Project to add issues to | ❌ | - |

## Usage

### Standard TODO scanning

```yaml
steps:
  - name: Create issues from TODOs
    uses: devantler-tech/actions/create-issues-from-todos@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
```

### With project integration

```yaml
steps:
  - name: Create issues from TODOs
    uses: devantler-tech/actions/create-issues-from-todos@main
    with:
      app-id: ${{ vars.APP_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      project: "organization/devantler-tech/1"
```
