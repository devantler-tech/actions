#!/usr/bin/env bash
# Fixture counterpart to test-automated-commits-signed.sh.
#
# That guard runs against `.github/workflows`, where both create-pull-request steps are
# correctly configured — so it reports PASS whatever its internals do. A parser regression
# would therefore ship green, and the two production workflows would keep vouching for it.
# This test drives the same guard over inputs it must ACCEPT and inputs it must REJECT, so
# each half is proven independently of the repository's current contents.
#
# The reject cases are one per way the token check has been observed to fail open or is
# expected to. `reject-pat-beside-approved` and `reject-bracketed-secret` are the two that
# actually did: an unrecognised reference riding alongside an approved one, which a scan
# that extracts recognised fragments cannot see. The accept cases are the positive controls
# — without them a guard that rejected everything would pass this test.

set -euo pipefail

guard="${1:-.github/tests/test-automated-commits-signed.sh}"
fixture_root="${2:-.github/tests/automated-commits-signed-fixtures}"

[[ -f "$guard" ]] || { echo "::error::guard $guard is missing"; exit 1; }
[[ -d "$fixture_root" ]] || { echo "::error::fixture root $fixture_root is missing"; exit 1; }

status=0
accepted=0
rejected=0

expect() {
  local name=$1 want=$2 dir="$fixture_root/$1" out rc=0
  if [[ ! -d "$dir" ]]; then
    echo "::error::fixture $name is missing — this case cannot prove anything"
    status=1
    return
  fi
  out="$(bash "$guard" "$dir" 2>&1)" || rc=$?

  if [[ "$want" == accept ]]; then
    accepted=$((accepted + 1))
    if ((rc != 0)); then
      echo "::error::$name must be ACCEPTED but the guard rejected it (rc=$rc)"
      printf '        %s\n' "$out"
      status=1
    fi
  else
    rejected=$((rejected + 1))
    if ((rc == 0)); then
      echo "::error::$name must be REJECTED but the guard passed it — this is a fail-open"
      printf '        %s\n' "$out"
      status=1
    fi
  fi
}

# Positive controls: a guard that rejects everything fails here.
expect accept-default-token        accept
expect accept-token-absent         accept
expect accept-app-token-fallback   accept

# Token source is not signing-capable.
expect reject-pat                  reject
expect reject-branch-token-pat     reject

# The measured fail-open: an unrecognised reference beside an approved one.
expect reject-pat-beside-approved  reject
expect reject-bracketed-secret     reject

# Nothing resolvable to vet at all.
expect reject-literal              reject
expect reject-glued-literal        reject
expect reject-workflow-input       reject

# Trust must come from the step's `uses`, never from its id.
expect reject-impostor-app-step    reject

# The two vacuity controls inside the guard itself.
expect reject-unsigned             reject
expect reject-no-producer          reject

# Guard the guard: a miscounted table silently shrinks coverage.
if ((accepted < 3 || rejected < 10)); then
  echo "::error::coverage shrank — expected at least 3 accept and 10 reject cases, ran $accepted and $rejected"
  status=1
fi

if ((status == 0)); then
  echo "PASS: the signing guard accepted all $accepted approved fixtures and rejected all $rejected prohibited ones"
fi
exit "$status"
