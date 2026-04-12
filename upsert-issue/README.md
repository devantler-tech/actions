# Upsert Issue

Create, update, reopen, or close a GitHub issue by title. Finds an existing issue with the same title and updates it, or creates a new one. Supports controlling the issue state (`open` / `closed`) to manage issue lifecycle — e.g., auto-closing when a report has no violations and reopening when violations recur.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `title` | Title of the issue to create or update | ✅ | — |
| `body` | Body content of the issue | ❌ | — |
| `body-file` | Path to a file containing the body content (takes precedence over `body`) | ❌ | — |
| `labels` | Comma-separated list of labels to assign | ❌ | — |
| `open` | Whether the issue should be open (`true`) or closed (`false`) | ❌ | `true` |
| `close-comment` | Comment to post when closing the issue | ❌ | `✅ Resolved — closing this issue.` |
| `repository` | Target repository (`owner/repo`) | ❌ | `${{ github.repository }}` |
| `GITHUB_TOKEN` | GitHub token with `issues: write` permission | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `issue-number` | The number of the created or updated issue |
| `issue-url` | The URL of the created or updated issue |

## Usage

### Create or update an issue

```yaml
steps:
  - uses: devantler-tech/actions/upsert-issue@main
    with:
      title: "[report] My Report"
      body-file: report.md
```

### Close an issue when resolved

```yaml
steps:
  - uses: devantler-tech/actions/upsert-issue@main
    with:
      title: "[report] My Report"
      body: "No violations found."
      open: "false"
      close-comment: "✅ All violations have been resolved."
```

### Conditional open/close based on a previous step

```yaml
steps:
  - id: report
    run: bun run report:my-report

  - uses: devantler-tech/actions/upsert-issue@main
    with:
      title: "[report] My Report"
      body-file: ${{ steps.report.outputs.report-path }}
      open: ${{ steps.report.outputs.has-violations }}
```
