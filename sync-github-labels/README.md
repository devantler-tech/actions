# Sync GitHub Labels

Sync GitHub labels from a configuration file. Creates, updates, or deletes labels to match the config, ensuring consistent labeling across repositories.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `config-file` | URL or path to the labels config file | ❌ | [devantler-tech labels](https://raw.githubusercontent.com/devantler-tech/actions/refs/heads/main/.github/labels.yaml) |
| `delete-other-labels` | Whether to delete labels not in the config | ❌ | `true` |

## Usage

### Default config

```yaml
steps:
  - name: Sync labels
    uses: devantler-tech/actions/sync-github-labels@main
```

### Custom config

```yaml
steps:
  - name: Sync labels
    uses: devantler-tech/actions/sync-github-labels@main
    with:
      config-file: "https://raw.githubusercontent.com/my-org/configs/main/labels.yaml"
```

### Preserve existing labels

```yaml
steps:
  - name: Sync labels
    uses: devantler-tech/actions/sync-github-labels@main
    with:
      delete-other-labels: "false"
```
