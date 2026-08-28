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
# The checksums file is served from the same release as the archive, so it is not an independent
# authority: an actor able to rewrite that release's assets could pair a genuinely-attested archive
# from a DIFFERENT version with a checksums entry naming it under this version's asset name, and both
# gates here would pass — attestation cannot tell versions apart, and the digest would match the
# substituted file. The post-install version assertion below is what rejects that substitution: a
# cli/cli build reports its own version truthfully, so an older archive is caught after extraction
# even though it clears both gates here. That leaves a same-version rewrite, which attestation
# already covers, since a rewritten archive cannot be re-attested by cli/cli's release workflow.
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

# Bind the archive to a digest this repository REVIEWED, not one the release served.
# Both gates above are satisfiable by a substituted archive: attestation cannot tell
# cli/cli releases apart, and the checksums file comes from the same mutable release as
# the asset, so an actor rewriting that release can pair a genuinely-attested archive from
# a DIFFERENT version with a matching checksums entry. The post-install version assertion
# below rejects an OLDER archive, but it is a floor (REQUIRED <= installed), so a
# same-or-newer substitution still installs and silently defeats version pinning.
# An exact match against the in-repo manifest is equality rather than a floor, and its
# value entered the repository through review rather than over the network.
#
# Enforcement is per row: an unknown version warns and falls through to the existing
# gates, so a consumer passing a custom gh-version is never blocked by a missing row.
# The manifest is read as plain text with awk and is never sourced, so a malformed or
# hostile line cannot execute anything.
digest_manifest="$(dirname "${BASH_SOURCE[0]}")/gh-release-digests.tsv"
manifest_row=""
if [ -f "$digest_manifest" ]; then
  # The "row:" marker carries ROW PRESENCE independently of the digest field's value.
  # Reading $4 alone conflates "no matching row" with "a matching row whose sha256 is
  # empty or absent", because awk yields an empty string for both. Those must diverge:
  # the first warns and falls through (an unknown version is not the consumer's fault),
  # while the second is a corrupted row that has to fail closed. Collapsing them is the
  # one outcome an actor who can edit this manifest would want, since blanking a field
  # is a far easier corruption than forging a digest.
  manifest_row=$(awk -F'\t' -v v="$REQUIRED" -v o="$os" -v a="$arch" \
    '$1 !~ /^#/ && $1 == v && $2 == o && $3 == a { print "row:" $4; exit }' "$digest_manifest")
else
  echo "::warning::No gh release digest manifest at $digest_manifest; installing v${REQUIRED} on the release-served digest alone."
fi

if [ -n "$manifest_row" ]; then
  pinned_digest=${manifest_row#row:}
  # A row that exists but is malformed must fail closed. Silently treating an unusable
  # value as "no row" would let a corrupted manifest downgrade this gate to a warning,
  # which is the one outcome an attacker editing it would want.
  # Matched with bash's own regex rather than `printf | grep -q`: under `set -o pipefail`
  # grep exits as soon as it matches, so printf can take SIGPIPE and turn a MATCHING
  # digest into a non-zero pipeline — rejecting a perfectly good manifest row.
  if ! [[ "$pinned_digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "::error::$digest_manifest has a malformed sha256 for v${REQUIRED} ${os}/${arch}; refusing to install it."
    exit 1
  fi
  if [ "$actual_digest" != "$pinned_digest" ]; then
    echo "::error::$asset does not match the digest this repository pinned for v${REQUIRED} ${os}/${arch} (pinned $pinned_digest, got $actual_digest); the release served a different archive than the one reviewed here. Refusing to install it."
    exit 1
  fi
  echo "Verified $asset against the reviewed digest pinned for v${REQUIRED} ${os}/${arch}."
elif [ -f "$digest_manifest" ]; then
  echo "::warning::$digest_manifest pins no digest for v${REQUIRED} ${os}/${arch}; installing on the release-served digest alone. Run 'bash .scripts/refresh-gh-digests.sh ${REQUIRED}' to pin it."
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
# Validate the candidate WHERE IT WAS EXTRACTED, and publish it only once every check has
# passed. Installing first and appending to GITHUB_PATH before validating would expose a
# rejected binary to every later step in the job: GITHUB_PATH is processed by the runner after
# the step ends regardless of its exit status, so a `continue-on-error` caller — or any caller
# that does not halt the job on this step — would inherit the very downgrade the checks below
# exist to reject. Nothing reaches install_dir or PATH until the candidate is proven.
candidate="$tmp/gh_${REQUIRED}_${os}_${arch}/bin/gh"
if [ ! -x "$candidate" ]; then
  echo "::error::Extracted archive does not contain an executable gh at the expected path."
  exit 1
fi

# Bind what was DOWNLOADED to what was REQUESTED. Attestation proves cli/cli built this
# archive but cannot say which version it is (every release attests from refs/heads/trunk),
# and the checksums file is served from the same mutable release as the archive — so a
# genuinely-attested OLDER archive paired with a matching checksums entry passes both gates
# above. A cli/cli build reports its own version truthfully, so asserting it here rejects
# that substitution using only signals already verified. Same `sort -V -C` comparison as the
# fast-return guard: success means REQUIRED <= installed.
installed=$("$candidate" --version | awk '/^gh version /{print $3; exit}')
if [ -z "$installed" ]; then
  echo "::error::Could not determine the downloaded gh version from 'gh --version' output."
  exit 1
fi
if ! printf '%s\n%s\n' "$REQUIRED" "$installed" | sort -V -C; then
  echo "::error::Downloaded gh ($installed) is older than the requested v${REQUIRED}; the downloaded archive is not the release it was published under. Refusing to use it."
  exit 1
fi

if ! "$candidate" skill --help >/dev/null 2>&1; then
  echo "::error::Downloaded gh does not expose the 'skill' command."
  exit 1
fi

# Every check passed — now publish it.
install_dir="${RUNNER_TEMP:-/tmp}/${INSTALL_NAMESPACE}/bin"
mkdir -p "$install_dir"
install "$candidate" "$install_dir/gh"
echo "$install_dir" >> "$GITHUB_PATH"
export PATH="$install_dir:$PATH"
hash -r
gh --version
