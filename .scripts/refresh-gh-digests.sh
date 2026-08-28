#!/usr/bin/env bash
# Refresh the reviewed version-to-digest rows in .scripts/gh-release-digests.tsv.
#
# Usage:  bash .scripts/refresh-gh-digests.sh <version>        # e.g. 2.90.0
#
# Fetches the checksums file cli/cli publishes for that release, extracts the digests for
# the four assets ensure-gh-skill.sh can install, and rewrites those rows in place. The
# point is that the value entering the repository is the one the release actually
# published, transcribed mechanically rather than by hand, and then reviewed in a pull
# request before anything trusts it.
#
# Run this from CI or locally when bumping the version ensure-gh-skill.sh requires, and
# review the resulting diff like any other change. Rows for other versions are preserved,
# so a consumer pinning an older gh keeps its guarantee.
set -euo pipefail

version="${1:-}"
if [ -z "$version" ]; then
  echo "usage: $0 <version>   (e.g. $0 2.90.0)" >&2
  exit 2
fi
# Reject anything that is not a plain dotted version before it reaches a URL: this argument
# is the only untrusted input here, and it must never be able to redirect the fetch.
# Bash-native match, not `printf | grep -q`: with `set -o pipefail` an early grep exit can
# SIGPIPE the printf and invert the result.
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "::error::version must be a bare X.Y.Z (got '$version')" >&2
  exit 2
fi

manifest="$(dirname "${BASH_SOURCE[0]}")/gh-release-digests.tsv"
if [ ! -f "$manifest" ]; then
  echo "::error::$manifest not found" >&2
  exit 1
fi

sums_url="https://github.com/cli/cli/releases/download/v${version}/gh_${version}_checksums.txt"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Fetching $sums_url"
if ! curl -fsSL -o "$tmp/sums" "$sums_url"; then
  echo "::error::could not fetch the checksums file for v${version}; is that a published cli/cli release?" >&2
  exit 1
fi

# The exact asset set ensure-gh-skill.sh knows how to install. Keeping this list in step
# with that script's os/arch cases is what stops the manifest from silently pinning fewer
# platforms than the installer actually serves.
rows=""
for pair in "linux amd64 tar.gz" "linux arm64 tar.gz" "macOS amd64 zip" "macOS arm64 zip"; do
  # shellcheck disable=SC2086
  set -- $pair
  os=$1 arch=$2 ext=$3
  asset="gh_${version}_${os}_${arch}.${ext}"
  digest=$(awk -v want="$asset" '$2 == want { print $1; exit }' "$tmp/sums")
  if [ -z "$digest" ]; then
    echo "::error::$asset is absent from the checksums file for v${version}; refusing to write a partial manifest." >&2
    exit 1
  fi
  if ! [[ "$digest" =~ ^[0-9a-f]{64}$ ]]; then
    echo "::error::checksums file gave a malformed digest for $asset: '$digest'" >&2
    exit 1
  fi
  rows="${rows}${version}\t${os}\t${arch}\t${digest}\n"
done

# Drop any existing rows for this version, keep everything else (comments, other
# versions), then append the freshly fetched set and sort the data rows for a stable diff.
{
  grep -E '^[[:space:]]*(#|$)' "$manifest" || true
} > "$tmp/header"
{
  grep -vE '^[[:space:]]*(#|$)' "$manifest" | awk -F'\t' -v v="$version" '$1 != v' || true
  printf '%b' "$rows"
} | sort -t"$(printf '\t')" -k1,1V -k2,2 -k3,3 > "$tmp/data"

cat "$tmp/header" "$tmp/data" > "$tmp/manifest"
mv "$tmp/manifest" "$manifest"

echo "Pinned $(printf '%b' "$rows" | grep -c . ) asset digest(s) for v${version} in $manifest"
