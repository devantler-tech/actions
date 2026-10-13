#!/usr/bin/env bash
# Execute the native recovery test's cleanup function against controlled observations.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
# Reject any cleanup result that cannot prove removal or retain the test failure.
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
sed -n '/^cleanup() {$/,/^}$/p' "$root/.github/tests/test-go-postgresql-recovery.sh" >"$scratch/cleanup.sh"
[[ -s "$scratch/cleanup.sh" ]] || fail 'native cleanup function was not found'
mkdir "$scratch/bin"
cat >"$scratch/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1" >>"$CLEANUP_CALLS"
case "$1" in
  inspect)
    [[ "$2" == "$CLEANUP_ID" && "$3" == --format ]] || exit 98
    [[ "$4" == '{{range .Mounts}}{{if and (eq .Type "volume") (eq .Destination "/var/lib/postgresql/data")}}{{.Name}}{{"\n"}}{{end}}{{end}}' ]] || exit 98
    [[ "$CLEANUP_SCENARIO" != inspect-failed ]] || exit 23
    case "$CLEANUP_SCENARIO" in
      empty) ;;
      whitespace) printf ' \t\n' ;;
      malformed) printf 'not-a-volume\n' ;;
      multiple) printf '%s\n%s\n' "$CLEANUP_VOLUME" "$CLEANUP_VOLUME" ;;
      *) printf '%s\n' "$CLEANUP_VOLUME" ;;
    esac
    ;;
  rm)
    [[ "$*" == "rm --force --volumes $CLEANUP_ID" ]] || exit 98
    [[ "$CLEANUP_SCENARIO" != remove-failed ]] || exit 23
    ;;
  ps)
    [[ "$*" == "ps --all --no-trunc --filter id=$CLEANUP_ID --format {{.ID}}" ]] || exit 98
    [[ "$CLEANUP_SCENARIO" != container-read-failed ]] || exit 23
    [[ "$CLEANUP_SCENARIO" != container-remains ]] || printf '%s\n' "$CLEANUP_ID"
    ;;
  volume)
    [[ "$*" == "volume ls --filter name=$CLEANUP_VOLUME --format {{.Name}}" ]] || exit 98
    [[ "$CLEANUP_SCENARIO" != volume-read-failed ]] || exit 23
    [[ "$CLEANUP_SCENARIO" != volume-remains ]] || printf '%s\n' "$CLEANUP_VOLUME"
    ;;
  *) exit 98 ;;
esac
DOCKER
chmod +x "$scratch/bin/docker"
export PATH="$scratch/bin:$PATH" CLEANUP_ID=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export CLEANUP_VOLUME=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
for CLEANUP_SCENARIO in valid empty whitespace malformed multiple inspect-failed remove-failed container-remains volume-remains container-read-failed volume-read-failed; do
  export CLEANUP_SCENARIO CLEANUP_CALLS="$scratch/$CLEANUP_SCENARIO.calls"
  mkdir "$scratch/$CLEANUP_SCENARIO"
  rc=0
  bash -c 'source "$1"; scratch="$2"; container="$CLEANUP_ID"; true; cleanup' \
    -- "$scratch/cleanup.sh" "$scratch/$CLEANUP_SCENARIO" >"$scratch/output" 2>"$scratch/error" || rc=$?
  [[ ! -d "$scratch/$CLEANUP_SCENARIO" ]] || fail 'owned scratch directory survived cleanup'
  if [[ "$CLEANUP_SCENARIO" == valid ]]; then
    [[ "$rc" == 0 && "$(grep -c '^volume$' "$CLEANUP_CALLS")" == 1 ]] || fail 'valid cleanup did not verify the recorded volume'
  else
    [[ "$rc" != 0 ]] || fail "unproven cleanup ($CLEANUP_SCENARIO) reported success"
  fi
  [[ "$(grep -c '^rm$' "$CLEANUP_CALLS")" == 1 ]] || fail 'owned container removal was omitted or repeated'
done
# A complete cleanup must also retain the interrupted test's original failure.
export CLEANUP_SCENARIO=valid CLEANUP_CALLS="$scratch/prior-failure.calls"
mkdir "$scratch/prior-failure"
rc=0
bash -c 'source "$1"; scratch="$2"; container="$CLEANUP_ID"; (exit 7); cleanup' \
  -- "$scratch/cleanup.sh" "$scratch/prior-failure" >"$scratch/output" 2>"$scratch/error" || rc=$?
[[ "$rc" == 7 ]] || fail 'successful cleanup hid the original test failure'
printf 'PASS: native cleanup requires complete volume observations and verified removal\n'
