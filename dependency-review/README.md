# Dependency Review

Scan a pull request's dependency changes for known-vulnerable packages and
disallowed licenses, using [GitHub Dependency Review][dra]. It diffs the base
and head of a PR and surfaces any newly-introduced dependency that carries a
known vulnerability or a license outside your policy.

This composite wraps `actions/dependency-review-action` (SHA-pinned) and exposes
the most useful knobs as inputs. It is **non-blocking by default**: `warn-only`
defaults to `true`, so findings are reported as warnings and the check always
succeeds — safe to roll out org-wide as a Required Workflow without blocking
existing PRs. Set `warn-only` to `"false"` to start enforcing, optionally
tightening `fail-on-severity`.

> The underlying action only produces a meaningful diff on `pull_request` /
> `pull_request_target` events (or when `base-ref` / `head-ref` are supplied
> explicitly). Gate the calling job accordingly. `allow-licenses` and
> `deny-licenses` are mutually exclusive — set at most one.

[dra]: https://github.com/actions/dependency-review-action

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `fail-on-severity` | Block the PR on vulnerabilities of this severity or higher (`low`, `moderate`, `high`, `critical`). Only applies when `warn-only` is false. | ❌ | `critical` |
| `fail-on-scopes` | Comma-separated dependency scopes to block on (`runtime`, `development`, `unknown`). Defaults to `runtime` so dev-only vulnerabilities don't block. | ❌ | `runtime` |
| `allow-licenses` | Comma-separated allow-list of SPDX licenses; a dependency under any other license fails the check. Mutually exclusive with `deny-licenses`. | ❌ | - |
| `deny-licenses` | Comma-separated deny-list of SPDX licenses; a dependency under any of these fails the check. Mutually exclusive with `allow-licenses`. | ❌ | - |
| `comment-summary-in-pr` | Post the review summary as a PR comment (`always`, `on-failure`, `never`). Anything but `never` requires the calling job to grant `pull-requests: write`. | ❌ | `never` |
| `base-ref` | Base git ref to diff from. Defaulted automatically on `pull_request` / `pull_request_target`; required for other events. | ❌ | - |
| `head-ref` | Head git ref to diff to. Defaulted automatically on `pull_request` / `pull_request_target`; required for other events. | ❌ | - |
| `retry-on-snapshot-warnings` | Retry when the dependency snapshot is not yet available, instead of failing immediately. | ❌ | `false` |
| `warn-only` | Report every finding as a warning and always succeed, overriding `fail-on-severity`. Defaults to `true` so the check can roll out org-wide without blocking PRs; set to `false` to enforce. | ❌ | `true` |
| `repo-token` | Token used to read dependency changes and (optionally) post the PR comment. | ❌ | `${{ github.token }}` |

## Outputs

| Name | Description |
|------|-------------|
| `comment-content` | The prepared dependency-review report comment (markdown). |
| `dependency-changes` | All dependency changes in the PR (JSON). |
| `vulnerable-changes` | Vulnerable dependency changes (JSON). |
| `invalid-license-changes` | Dependency changes with disallowed licenses (JSON). |
| `denied-changes` | Denied dependency changes (JSON). |

## Permissions

The composite reads the dependency diff with `contents: read`. Posting a PR
comment (`comment-summary-in-pr` ≠ `never`) additionally requires the **calling
job** to grant `pull-requests: write` — a composite cannot declare it.

## Usage

### Non-blocking (default) — warn on findings

```yaml
jobs:
  dependency-review:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - name: 📑 Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false

      - name: 🛡️ Review dependencies
        uses: devantler-tech/actions/dependency-review@main
```

### Enforce — fail on high-severity vulnerabilities and post a comment

```yaml
jobs:
  dependency-review:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write # required for comment-summary-in-pr
    steps:
      - name: 📑 Checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          persist-credentials: false

      - name: 🛡️ Review dependencies
        uses: devantler-tech/actions/dependency-review@main
        with:
          warn-only: "false"
          fail-on-severity: high
          comment-summary-in-pr: on-failure
```
