# Setup KSail CLI

> **Frozen legacy reference.** For new integrations and contributions, use the
> [maintained setup-ksail-cli guide](https://github.com/devantler-tech/.github/blob/main/actions/setup-ksail-cli/README.md)
> and [contribution guide](https://github.com/devantler-tech/.github/blob/main/CONTRIBUTING.md).
> The examples below describe legacy consumers, not a new-setup recommendation.
> Keep existing calls pinned to a reviewed full commit SHA; do not copy floating
> refs or change a consumer's automation without reviewing its migration.

Install the [KSail](https://github.com/devantler-tech/ksail) CLI via Homebrew for managing Kubernetes clusters.

Uses the released Homebrew channel and installs the `devantler-tech/tap/ksail` cask
from the first-party tap, trusting that tap before tapping it (Homebrew 6 refuses
to tap an untrusted tap that contains casks). Supported runners are macOS ARM64
and Linux AMD64/ARM64, matching KSail's published cask archives. Tap and download
failures use bounded retries; a trust failure stops installation immediately.

## Usage

```yaml
steps:
  - name: Setup KSail CLI
    uses: devantler-tech/actions/setup-ksail-cli@main
```
