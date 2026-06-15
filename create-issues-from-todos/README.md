# Create Issues from TODOs

Scan code for TODO comments and automatically create corresponding GitHub issues. Authenticates via GitHub App, locates TODOs with file and line references, and can optionally add issues to a GitHub Project.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `client-id` | GitHub App Client ID (preferred over the deprecated `app-id`) | ❌¹ | - |
| `app-id` | GitHub App ID. **Deprecated** — use `client-id` instead | ❌¹ | - |
| `app-private-key` | GitHub App Private Key | ✅ | - |
| `project` | GitHub Project to add issues to | ❌ | - |

¹ Provide exactly one of `client-id` or `app-id`. Prefer `client-id`: `actions/create-github-app-token` has deprecated `app-id`, so passing it emits a `Input 'app-id' has been deprecated` warning.

## Usage

### Standard TODO scanning

```yaml
steps:
  - name: Create issues from TODOs
    uses: devantler-tech/actions/create-issues-from-todos@main
    with:
      client-id: ${{ vars.APP_CLIENT_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
```

### With project integration

```yaml
steps:
  - name: Create issues from TODOs
    uses: devantler-tech/actions/create-issues-from-todos@main
    with:
      client-id: ${{ vars.APP_CLIENT_ID }}
      app-private-key: ${{ secrets.APP_PRIVATE_KEY }}
      project: "organization/devantler-tech/1"
```
