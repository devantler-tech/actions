#!/usr/bin/env bash
# Idempotent wrapper around `gh skill install`.
#
# A transient GitHub API failure can leave the target skill directory present
# even though `gh skill install` exits non-zero. A plain retry then fails with
# "skills already installed" instead of retrying the incomplete install. Recover
# only from that exact state by retrying once with --force; preserve every other
# failure as-is so real install errors still fail the calling check.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "::error::gh-skill-install.sh: no install arguments given" >&2
  exit 2
fi

has_force=false
for arg in "$@"; do
  if [ "$arg" = "--force" ]; then
    has_force=true
    break
  fi
done

stdout=$(mktemp)
stderr=$(mktemp)
out=$(mktemp)
trap 'rm -f "$stdout" "$stderr" "$out"' EXIT

if gh skill install "$@" >"$stdout" 2>"$stderr"; then
  cat "$stdout"
  cat "$stderr" >&2
  exit 0
else
  status=$?
fi

cat "$stdout"
cat "$stderr" >&2
cat "$stdout" "$stderr" >"$out"

if [ "$has_force" = false ] && grep -Eq '^skills already installed: .*\(use --force to overwrite\)' "$out"; then
  echo "::warning::gh skill install reported an already-installed skill; retrying once with --force." >&2
  gh skill install "$@" --force
  exit $?
fi

exit "$status"
