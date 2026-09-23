#!/usr/bin/env bash
# All paths are relative to the checkout, except the absolute scanner executable.
# JSON mode returns zero even for findings. Judge findings separately, and never
# let an operational failure or malformed stream become a successful verdict.
set -euo pipefail
scanner="$1" module="$2" allow_file="${3-}" output_file="${4-}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rc=0
(cd "$module" && "$scanner" -format=json -scan=symbol ./...) >"$work/scan.json" || rc=$?
if [[ -n "$output_file" ]]; then
  cp "$work/scan.json" "$output_file"
fi
if ((rc != 0)); then
  echo "::error::govulncheck failed to run (exit $rc): operational error, not a scan result."
  exit "$rc"
fi
if ! jq -ers -f "$script_dir/reachable.jq" "$work/scan.json" >"$work/called.json"; then
  echo '::error::govulncheck returned invalid scan output; no successful verdict is possible.'
  exit 2
fi

# Keep the existing allow-file format: whitespace-separated IDs, # comments and
# blank lines. Only complete IDs match; a prefix or malformed entry accepts none.
: >"$work/allow.txt"
if [[ -n "$allow_file" ]]; then
  if [[ -f "$allow_file" ]]; then
    sed 's/#.*//' "$allow_file" | tr -s ' \t\r' '\n' >"$work/allow.txt"
  else
    echo '::warning::The requested allow-file was not found; scanning in strict mode.'
  fi
fi

blocking=0
while IFS= read -r id; do
  if grep -qxF "$id" "$work/allow.txt"; then
    echo "$id - ALLOWLISTED"
  else
    echo "$id - BLOCKING (https://pkg.go.dev/vuln/$id)"
    blocking=1
  fi
done < <(jq -r '.[]' "$work/called.json")
if ((blocking)); then
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo 'verdict=blocking' >>"$GITHUB_OUTPUT"; fi
  echo '::error::Reachable vulnerabilities are not accepted. Upgrade the affected dependency, remove the call, or document an explicit risk acceptance.'
  exit 1
fi
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo 'verdict=clean' >>"$GITHUB_OUTPUT"; fi
echo 'No blocking vulnerabilities (accepted advisories, if any, are listed above).'
