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

tmp=$(mktemp -d)
asset="gh_${REQUIRED}_${os}_${arch}.${ext}"
url="https://github.com/cli/cli/releases/download/v${REQUIRED}/${asset}"
echo "Downloading $url"
if [ "$ext" = "zip" ]; then
  if ! command -v unzip >/dev/null 2>&1; then
    echo "::error::unzip is required to extract the macOS gh release archive but is not available on PATH."
    exit 1
  fi
  curl -fsSL -o "$tmp/$asset" "$url"
  unzip -q "$tmp/$asset" -d "$tmp"
else
  curl -fsSL "$url" | tar -xzC "$tmp"
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
