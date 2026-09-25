#!/usr/bin/env bash
set -euo pipefail

captured=$(printf 'needle\n') || exit "$?"
grep -q needle <<< "$captured"

# This is prose, not an executable pipeline.
printf '%s\n' 'producer | grep -q needle'
