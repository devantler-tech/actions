#!/usr/bin/env bash
# Shared gh bootstrap for the agent-skills composite actions.
#
# Ensures a `gh` CLI that exposes the `gh skill` command is on PATH, installing a
# pinned cli/cli release when the runner's gh is missing or too old. Invoked by both
# setup-agent-skills/ and update-agent-skills/ via
#   bash "${GITHUB_ACTION_PATH}/../.scripts/ensure-gh-skill.sh"
# so the logic lives in one place — composite actions cannot share steps directly,
# but they can share a script bundled in the same repository (resolved relative to
# ${GITHUB_ACTION_PATH}, which works for both local `uses: ./<action>` callers and
# external `uses: devantler-tech/actions/<action>@<ref>` consumers).
#
# Required environment:
#   REQUIRED          minimum gh version to guarantee (e.g. 2.81.0)
#   INSTALL_NAMESPACE per-action subdirectory under $RUNNER_TEMP for the installed
#                     binary, so concurrent callers never clobber each other
set -euo pipefail

: "${REQUIRED:?REQUIRED (minimum gh version) must be set}"
: "${INSTALL_NAMESPACE:?INSTALL_NAMESPACE must be set}"

# Bounded retry for the network download below — a transient github.com release
# 5xx or DNS/TLS blip must not red a required check (reliability pillar, #247).
# Resolved relative to this script's own dir (alongside retry.sh), so it works for
# both local `uses: ./<action>` and external `uses: …@<ref>` callers.
retry() { bash "$(dirname "${BASH_SOURCE[0]}")/retry.sh" "$@"; }

if command -v gh >/dev/null 2>&1 && gh skill --help >/dev/null 2>&1; then
  current=$(gh --version | awk '/^gh version /{print $3; exit}')
  if [ -z "$current" ]; then
    echo "::error::Could not determine the installed gh version from 'gh --version' output."
    exit 1
  fi
  if printf '%s\n%s\n' "$REQUIRED" "$current" | sort -V -C; then
    echo "Installed gh ($current) already supports 'gh skill'."
    exit 0
  fi
fi

case "$(uname -s)" in
  Linux)   os=linux;  ext=tar.gz ;;
  Darwin)  os=macOS;  ext=zip ;;
  *) echo "::error::Automatic gh install is only supported on Linux and macOS. On $(uname -s) (e.g. Windows), preinstall gh >= ${REQUIRED} on the runner before this step."; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "::error::Unsupported arch: $(uname -m)"; exit 1 ;;
esac

# The release archive is executable input.  Verify its GitHub artifact
# attestation with the runner-provided gh before trusting it; downloading a
# checksum beside the archive would leave both files under the same mutable
# release-asset trust boundary.  Do not bootstrap the verifier from the asset
# it is about to verify.
if ! command -v gh >/dev/null 2>&1 || ! gh attestation --help >/dev/null 2>&1; then
  echo "::error::A trusted runner-provided gh with 'gh attestation' support is required to verify the gh release archive before installation."
  exit 1
fi

tmp=$(mktemp -d)
asset="gh_${REQUIRED}_${os}_${arch}.${ext}"
url="https://github.com/cli/cli/releases/download/v${REQUIRED}/${asset}"
echo "Downloading $url"
if [ "$ext" = "zip" ] && ! command -v unzip >/dev/null 2>&1; then
  echo "::error::unzip is required to extract the macOS gh release archive but is not available on PATH."
  exit 1
fi
# Download (network — retried) to a file, then extract (local — not retried). The
# Linux path downloads to a file rather than streaming `curl | tar` so the network
# pull is a single retryable command.
retry curl -fsSL -o "$tmp/$asset" "$url"

# Attestation proves cli/cli's release workflow built this archive. It does NOT prove the archive is
# the one published for v${REQUIRED}: every cli/cli release is attested from refs/heads/trunk, so the
# certificate's source ref is identical across versions and cannot distinguish them. (Verified against
# v2.81.0: sourceRepositoryRef is refs/heads/trunk, so pinning --source-ref refs/tags/v<version> would
# reject every legitimate artifact.) The release's own checksums file is what binds a digest to a
# version, so both checks are required and neither is sufficient alone.
#
# Residual risk, stated honestly: the checksums file is served from the same release as the archive,
# so it is not an independent authority. An actor able to rewrite that release's assets could pair a
# genuinely-attested archive from a DIFFERENT version with a checksums entry naming it under this
# version's asset name, and both gates above would pass — attestation cannot tell versions apart, and
# the digest would match the substituted file. Closing that needs a version-to-digest pin held in
# THIS repository (reviewed, not fetched); no independently-signed upstream manifest exists to use
# instead. Tracked separately rather than widened into this change.
sums="gh_${REQUIRED}_checksums.txt"
retry curl -fsSL -o "$tmp/$sums" "https://github.com/cli/cli/releases/download/v${REQUIRED}/${sums}"

expected_digest=$(awk -v want="$asset" '$2 == want { print $1; exit }' "$tmp/$sums")
if [ -z "$expected_digest" ]; then
  echo "::error::$sums for v${REQUIRED} lists no entry for $asset; refusing to install it."
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual_digest=$(sha256sum "$tmp/$asset" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
  actual_digest=$(shasum -a 256 "$tmp/$asset" | awk '{print $1}')
else
  echo "::error::Neither sha256sum nor shasum is available to verify $asset against $sums."
  exit 1
fi

if [ "$actual_digest" != "$expected_digest" ]; then
  echo "::error::$asset does not match the digest published for v${REQUIRED} (expected $expected_digest, got $actual_digest); refusing to install it."
  exit 1
fi

# --signer-workflow narrows this from "any workflow in cli/cli" to the release workflow specifically.
# If cli/cli ever renames that workflow this fails closed: read the new path from
# `gh attestation verify <asset> --repo cli/cli --format json` (.buildSignerURI) and update it here.
if ! gh attestation verify "$tmp/$asset" \
  --repo cli/cli \
  --signer-workflow 'cli/cli/.github/workflows/deployment.yml'; then
  echo "::error::GitHub artifact attestation verification failed for $asset; refusing to install it."
  exit 1
fi
if [ "$ext" = "zip" ]; then
  unzip -q "$tmp/$asset" -d "$tmp"
else
  tar -xzC "$tmp" -f "$tmp/$asset"
fi
install_dir="${RUNNER_TEMP:-/tmp}/${INSTALL_NAMESPACE}/bin"
mkdir -p "$install_dir"
install "$tmp/gh_${REQUIRED}_${os}_${arch}/bin/gh" "$install_dir/gh"
echo "$install_dir" >> "$GITHUB_PATH"
export PATH="$install_dir:$PATH"
hash -r
gh --version
if ! gh skill --help >/dev/null 2>&1; then
  echo "::error::Installed gh still does not expose the 'skill' command."
  exit 1
fi
