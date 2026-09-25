# Validate retired repository links

Catch documentation links that still send readers to a retired GitHub repository.
Each consumer declares its retired repositories, files or directories to scan,
and documented exceptions for historical records. The validator is read-only and
does not call GitHub, follow links, or infer retirement from a repository name.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `enabled` | Opt in to validation; exactly `true` or `false`. | No | `false` |
| `config-file` | JSON configuration relative to `working-directory`. | No | `.github/retired-repo-links.json` |
| `working-directory` | Consumer directory, relative to `GITHUB_WORKSPACE` or absolute. | No | `.` |

## Outputs

| Name | Description |
|------|-------------|
| `validated` | `true` after a complete successful scan; empty when disabled or unsuccessful. |

## Usage

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false
  - uses: devantler-tech/actions/validate-retired-repo-links@<full-commit-sha>
    with:
      enabled: "true"
```

Omitted or false `enabled` inputs do not install Go, read configuration or scan
files. Enabled runs install the Go version from this action's module and build a
standard-library-only validator from the pinned action revision. The caller's Go
module and workspace are not used. That Go stays on `PATH` for later steps in the
same job, so run the action in its own job, or set up your own Go version again
after it. Linux and macOS runners are supported.

Consumer adoption and removal of the temporary `enabled` flag are tracked in
[#1350](https://github.com/devantler-tech/actions/issues/1350).

## Configuration

Create `.github/retired-repo-links.json` in the consumer repository:

```json
{
  "version": 1,
  "repositories": ["devantler-tech/reusable-workflows"],
  "paths": ["README.md", "docs"],
  "exceptions": [
    {
      "path": "docs/history.md",
      "repository": "devantler-tech/reusable-workflows",
      "reason": "Historical record of the workflow migration."
    }
  ]
}
```

Paths are exact relative file or directory names; colons are ordinary filename
characters. Directories are scanned recursively, including hidden files. Glob
patterns, absolute paths, parent traversal and symlinks are unsupported. Every
configured path must exist; overlapping paths are scanned only once. Select
documentation roots instead of the entire checkout to avoid scanning Git
internals and dependency directories.

Repositories use ASCII `owner/repository` names, matched without regard to ASCII
case. The check recognizes literal HTTP(S) URLs on `github.com`, `www.github.com`
and `raw.githubusercontent.com`, including file, issue, fragment and clone links.
Similar names such as `retired-tools` remain distinct, and so do names followed by
a non-ASCII letter. Plain prose, relative links, encoded URL components, SSH URLs
and other GitHub hosts are outside scope. The scheme must start at a text
boundary, so `nothttps://...` does not count; typographic quotes and other
non-ASCII punctuation count as boundaries. Paired underscore emphasis and one- or
two-tilde strikethrough around a URL are recognized, nested in either order.
Unpaired underscore repository suffixes remain literal; this scanner does not
render arbitrary Markdown.

Exceptions apply only to an exact file and one configured repository, and require
a nonempty reason. They allow every matching link in that file, so reserve them
for historical records, not active usage instructions. No default exception hides
the consumer's README, instruction files or changelog.

Malformed configuration, unknown fields, missing paths, read errors, files over
16 MiB, and a scope containing no text files fail visibly. Binary or non-UTF-8
files are counted and skipped. Diagnostics name the file, line and retired
repository without printing document content or URL query parameters. Success
reports how many text files were checked and historical links were allowed.

## Local validation

With Go installed and a checkout of the pinned Actions revision:

```bash
GOWORK=off go -C /path/to/actions/validate-retired-repo-links run -mod=readonly . \
  --root /path/to/consumer --config .github/retired-repo-links.json
```

The CLI always validates; the opt-in belongs to the composite action. Exit codes
are `0` for a complete clean scan, `1` for retired links, and `2` for configuration,
argument or filesystem errors.

```bash
go -C validate-retired-repo-links test -race -cover ./...
go -C validate-retired-repo-links vet ./...
```
