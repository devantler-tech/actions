#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workflow="$repo_root/.github/workflows/create-release.yaml"

if ! grep -qF \
  'run: npx semantic-release@25.0.3 --success false --fail false' "$workflow"; then
  echo "create-release must disable semantic-release success and fail hooks" >&2
  exit 1
fi

if ! grep -qF 'permission-contents: write' "$workflow"; then
  echo "create-release must retain contents:write for tags and releases" >&2
  exit 1
fi

if grep -Eq 'permission-(issues|pull-requests):' "$workflow"; then
  echo "create-release must not request issue or pull-request write access" >&2
  exit 1
fi

echo "semantic-release issue side effects are disabled at least privilege"
