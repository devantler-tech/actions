#!/usr/bin/env bash
# Guards the actionlint arguments both MegaLinter gates pass (devantler-tech/ksail#6360).
#
# actionlint (<=1.7.12, bundled in MegaLinter) rejects the documented `concurrency.queue`
# key with `unexpected key "queue" for "concurrency" section`. Without an ignore, every
# consumer that serializes runs with `queue: max` fails lint. The ignore must stay NARROW:
# a pattern that also swallowed other unexpected concurrency keys would hide real typos.
#
# Asserted:
#   1. lint.yaml and validate-go-project.yaml pass identical ACTION_ACTIONLINT_ARGUMENTS;
#   2. those arguments keep the code-quality ignore and carry the queue ignore;
#   3. the queue pattern matches actionlint's real queue message and does NOT match the
#      same message for any other key;
#   4. the pattern contains no whitespace or quotes, so MegaLinter's argument split passes
#      it to actionlint as one token.
# Each assertion is then proven to fire on a bad variant (run with no arguments).

set -euo pipefail

queue_pattern='unexpected.key..queue..for..concurrency..section'

megalinter_args() {
  yq -r '[.jobs[].steps[]? | select((.uses // "") | test("^oxsecurity/megalinter/")) | .env.ACTION_ACTIONLINT_ARGUMENTS // ""] | .[0] // ""' "$1"
}

# check <lint-args> <validate-go-args>: prints one line per violation, returns 1 on any.
check() {
  local lint_args="$1" go_args="$2" status=0 tok found

  if [[ -z "$lint_args" || -z "$go_args" ]]; then
    echo "a MegaLinter gate has no ACTION_ACTIONLINT_ARGUMENTS"
    return 1
  fi
  if [[ "$lint_args" != "$go_args" ]]; then
    echo "lint.yaml and validate-go-project.yaml pass different actionlint arguments ('$lint_args' vs '$go_args')"
    status=1
  fi

  read -r -a tokens <<<"$lint_args"
  found=0
  for ((i = 0; i < ${#tokens[@]}; i++)); do
    [[ "${tokens[$i]}" == "-ignore" ]] || continue
    tok="${tokens[$((i + 1))]:-}"
    [[ "$tok" == "code-quality" ]] && found=$((found | 1))
    [[ "$tok" == "$queue_pattern" ]] && found=$((found | 2))
  done
  if (( (found & 1) == 0 )); then
    echo "the code-quality ignore is missing"
    status=1
  fi
  if (( (found & 2) == 0 )); then
    echo "the concurrency.queue ignore '$queue_pattern' is missing, so consumers using queue: max fail lint"
    status=1
  fi
  return "$status"
}

pattern_is_narrow() {
  local pattern="$1"
  [[ "$pattern" =~ [[:space:]\"\'] ]] && { echo "pattern contains whitespace or quotes"; return 1; }
  grep -Eq "$pattern" <<<'unexpected key "queue" for "concurrency" section. expected one of "cancel-in-progress", "group"' \
    || { echo "pattern does not match actionlint's queue message"; return 1; }
  if grep -Eq "$pattern" <<<'unexpected key "bogus" for "concurrency" section. expected one of "cancel-in-progress", "group"'; then
    echo "pattern also matches another unexpected concurrency key"
    return 1
  fi
}

status=0
lint_args="$(megalinter_args .github/workflows/lint.yaml)"
go_args="$(megalinter_args .github/workflows/validate-go-project.yaml)"

if ! out="$(check "$lint_args" "$go_args")"; then
  while IFS= read -r line; do echo "::error::$line"; done <<<"$out"
  status=1
fi
if ! out="$(pattern_is_narrow "$queue_pattern")"; then
  echo "::error::$out"
  status=1
fi

# Prove each assertion fires on a bad variant.
expect_fail() {
  local name="$1" expected="$2" out
  shift 2
  if out="$("$@")"; then
    echo "::error::ablation '$name' passed; the guard must reject it"
    status=1
  elif [[ "$out" != *"$expected"* ]]; then
    echo "::error::ablation '$name' failed for the wrong reason: $out"
    status=1
  fi
}

good='-ignore code-quality -ignore '"$queue_pattern"
expect_fail "queue ignore removed" "concurrency.queue ignore" check "-ignore code-quality" "-ignore code-quality"
expect_fail "gates drift" "different actionlint arguments" check "$good" "-ignore code-quality"
expect_fail "code-quality ignore removed" "code-quality ignore is missing" check "-ignore $queue_pattern" "-ignore $queue_pattern"
expect_fail "pattern too broad" "another unexpected concurrency key" pattern_is_narrow 'unexpected.key.*concurrency'
expect_fail "pattern with a space" "whitespace or quotes" pattern_is_narrow 'unexpected key..queue'
expect_fail "pattern that misses the message" "does not match" pattern_is_narrow 'unexpected.key..queue..for..concurrency.section'
if ! check "$good" "$good" >/dev/null; then
  echo "::error::the guard rejects a correct argument set"
  status=1
fi

if [[ "$status" -eq 0 ]]; then
  echo "Both MegaLinter gates ignore only actionlint's concurrency.queue message, in lockstep ✅"
fi
exit "$status"
