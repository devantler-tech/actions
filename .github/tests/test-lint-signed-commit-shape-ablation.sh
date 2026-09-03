#!/usr/bin/env bash

# Ablation for test-lint-signed-commit.sh's assertion 2 — the one that proves apply-fixes
# creates its commit through the createCommitOnBranch API. That assertion matches the
# mutation CALL, not the bare name, because the run block also carries the diagnostics
# `::error::createCommitOnBranch failed` and `.data.createCommitOnBranch.commit.oid`. It must
# therefore keep two properties at once, and each is proven here on a fixture (#1048):
#
#   * a call that is REFORMATTED — whitespace between `createCommitOnBranch(` and `input:`,
#     including a line break — is still recognised, so the guard does not fail a lane whose
#     call is entirely intact for the wrong reason;
#   * a lane that REMOVED the mutation and left only its diagnostics behind is still refused,
#     with this assertion's own message.
#
# The reformatted fixtures cannot be driven all the way to PASS: assertion 13b pins a digest
# of the signer's run text precisely so that an unaudited edit fails closed, and a reformat is
# such an edit. So the positive arm asserts the guard gets PAST assertion 2 — the failure it
# reports is the digest pin's, which names the right remedy — never assertion 2's message.

set -euo pipefail

guard=".github/tests/test-lint-signed-commit.sh"
signer=".github/workflows/apply-signed-fixes.yaml"
call_message="apply-fixes must create its commit with the createCommitOnBranch API"
digest_message="apply-fixes' run blocks changed"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# The guard derives the caller's expected `uses:` from the signer PATH it is given, so a fixture
# cannot simply be handed over as a second argument — it has to sit at the signer's own relative
# path. Each arm therefore runs the guard inside a throwaway tree that mirrors exactly the files
# it reads (the caller, the signer under test, and the guard itself), from that tree's root, with
# the guard's default arguments — the same invocation CI makes. Anything else fails for a reason
# unrelated to the assertion under test, which is the wrong-reason failure an ablation exists to
# rule out.
sandbox_guard() {
  local fixture="$1" dir
  dir="$(mktemp -d "$work/sandbox.XXXXXX")"
  mkdir -p "$dir/.github/workflows" "$dir/.github/tests"
  cp .github/workflows/lint.yaml "$dir/.github/workflows/lint.yaml"
  cp "$guard" "$dir/$guard"
  cp "$fixture" "$dir/$signer"
  (cd "$dir" && bash "$guard" 2>&1) || true
}

# Prove the sandbox is live before trusting any verdict from it: the pristine signer must PASS
# there, or a fixture that never reached the assertion would read as "did not fail".
cp "$signer" "$work/pristine.yaml"
out="$(sandbox_guard "$work/pristine.yaml")"
grep -qF 'PASS:' <<<"$out" ||
  fail "control — the pristine signer copy did not pass inside the sandbox, so the fixture path is not live: ${out}"
echo "ok: control — the pristine signer copy passes through the sandbox"

# The source spelling the fixtures rewrite. Assert it is present exactly once so a reformat of
# the real workflow cannot turn every arm below into a no-op that reports success.
# shellcheck disable=SC2016 # the literal GraphQL text, never a shell expansion
call='createCommitOnBranch(input: $input)'
count="$(grep -cF "$call" "$signer" || true)"
[[ "$count" == "1" ]] ||
  fail "expected exactly one '${call}' in ${signer}, found ${count}; the fixtures would not mutate"

run_guard() {
  sandbox_guard "$1"
}

# Positive arm: three reformats of the same intact call.
write_reformat() {
  local fixture="$1" spelling="$2"
  awk -v from="$call" -v to="$spelling" '{
    i = index($0, from)
    if (i > 0) { $0 = substr($0, 1, i - 1) to substr($0, i + length(from)) }
    print
  }' "$signer" >"$fixture"
  grep -qF "$spelling" "$fixture" || fail "fixture ${fixture} did not receive the reformatted call"
  ! grep -qF "$call" "$fixture" || fail "fixture ${fixture} still carries the original spelling"
}
# shellcheck disable=SC2016 # the literal GraphQL text, never a shell expansion
declare -a spellings=(
  'createCommitOnBranch( input: $input)'
  'createCommitOnBranch(  input:  $input )'
)
i=0
for spelling in "${spellings[@]}"; do
  i=$((i + 1))
  write_reformat "$work/reformat-$i.yaml" "$spelling"
  out="$(run_guard "$work/reformat-$i.yaml")"
  if grep -qF "$call_message" <<<"$out"; then
    fail "reformat ${i} (${spelling}): the guard refused an intact call for its spacing"
  fi
  grep -qF "$digest_message" <<<"$out" ||
    fail "reformat ${i} (${spelling}): expected the guard to reach the run-text digest pin; got: ${out}"
  echo "ok: reformat ${i} — recognised as the mutation call, refused only by the audited digest"
done

# The line-break reformat: the call split across two lines inside the run block. Written with
# a literal newline so the guard's whitespace collapse is what must bridge it.
fixture="$work/reformat-newline.yaml"
awk -v from="$call" '{
  i = index($0, from)
  if (i > 0) {
    indent = $0; sub(/[^ ].*$/, "", indent)
    print substr($0, 1, i - 1) "createCommitOnBranch("
    print indent "  input: $input)" substr($0, i + length(from))
  } else { print }
}' "$signer" >"$fixture"
if ! grep -qF 'createCommitOnBranch(' "$fixture" || grep -qF "$call" "$fixture"; then
  fail "the line-break fixture did not receive the split call"
fi
out="$(run_guard "$fixture")"
if grep -qF "$call_message" <<<"$out"; then
  fail "line-break reformat: the guard refused an intact call for its spacing"
fi
grep -qF "$digest_message" <<<"$out" ||
  fail "line-break reformat: expected the guard to reach the run-text digest pin; got: ${out}"
echo "ok: line-break reformat — recognised across the line break"

# Negative arm: the mutation is gone and only its diagnostics remain. The guard must refuse
# this with assertion 2's own message — the digest pin would also fire, but later, and a
# refusal that names only the digest would let a removed mutation read as an audit chore.
fixture="$work/removed.yaml"
awk -v from="$call" '{
  i = index($0, from)
  if (i > 0) { $0 = substr($0, 1, i - 1) "commitPlaceholder" substr($0, i + length(from)) }
  print
}' "$signer" >"$fixture"
! grep -qF "$call" "$fixture" || fail "the removed-mutation fixture still carries the call"
grep -qF '::error::createCommitOnBranch failed' "$fixture" ||
  fail "the removed-mutation fixture lost the diagnostics it exists to keep"
grep -qF '.data.createCommitOnBranch.commit.oid' "$fixture" ||
  fail "the removed-mutation fixture lost the response-path reference it exists to keep"
out="$(run_guard "$fixture")"
grep -qF "$call_message" <<<"$out" ||
  fail "removed mutation: expected assertion 2's refusal with only the diagnostics left; got: ${out}"
echo "ok: removed mutation — refused by assertion 2 although its diagnostics remain"

# Decoy arm: the mutation is gone AND a comment line spelling the call is left behind in
# the run block. A match over the raw run text would be satisfied by the comment alone;
# the assertion drops comment lines first, so the decoy must still be refused with its
# own message.
fixture="$work/decoy.yaml"
awk -v from="$call" '{
  i = index($0, from)
  if (i > 0) {
    indent = $0; sub(/[^ ].*$/, "", indent)
    print indent "# " from " is issued below by the signing helper"
    $0 = substr($0, 1, i - 1) "commitPlaceholder" substr($0, i + length(from))
  }
  print
}' "$signer" >"$fixture"
grep -qF "# $call" "$fixture" || fail "the decoy fixture did not receive the comment line"
[ "$(grep -cF "$call" "$fixture")" = "1" ] ||
  fail "the decoy fixture must carry the call text exactly once, inside the comment"
out="$(run_guard "$fixture")"
grep -qF "$call_message" <<<"$out" ||
  fail "decoy comment: a comment spelling the call satisfied the signing-API assertion; got: ${out}"
echo "ok: decoy comment — a comment spelling the call does not stand in for the mutation"

echo "PASS: the createCommitOnBranch assertion matches the call by shape, not by spacing, and still refuses a lane that dropped it"
