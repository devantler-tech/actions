#!/usr/bin/env bash
# Exercise the shipped installer with complete, failing and large version producers.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
mkdir -p "$scratch/bin" "$scratch/source" "$scratch/archive/gh_2.81.0_linux_amd64/bin" "$scratch/runtime"
cp "$root/.scripts/ensure-gh-skill.sh" "$root/.scripts/retry.sh" "$scratch/source/"
cat > "$scratch/version-producer" <<'PRODUCER'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  --version)
    printf 'gh version %s (fixture)\n' "$OBS_VERSION"
    # Many separate writes force the old early-exit reader to close a full pipe.
    for _ in {1..4096}; do
      printf 'additional release information that must be consumed before the producer exits\n'
    done
    # Parsing the first header remains distinct from printing every matching line.
    printf 'gh version 0.0.1 (later header)\n'
    touch "$OBS_COMPLETE"
    exit "$OBS_VERSION_EXIT"
    ;;
  skill) exit 0 ;;
  *) exit 2 ;;
esac
PRODUCER
cat > "$scratch/bin/uname" <<'UNAME'
#!/usr/bin/env bash
case "$1" in -s) echo Linux ;; -m) echo "$OBS_ARCH" ;; *) exit 2 ;; esac
UNAME
cat > "$scratch/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" == 4 && "$1" == -fsSL && "$2" == -o ]] || exit 2
case "$4" in
  https://github.com/cli/cli/releases/download/v2.81.0/gh_2.81.0_linux_amd64.tar.gz) cp "$OBS_ARCHIVE" "$3" ;;
  https://github.com/cli/cli/releases/download/v2.81.0/gh_2.81.0_checksums.txt) cp "$OBS_CHECKSUMS" "$3" ;;
  *) exit 2 ;;
esac
CURL
chmod +x "$scratch/version-producer" "$scratch/bin/uname" "$scratch/bin/curl"
cp "$scratch/version-producer" "$scratch/archive/gh_2.81.0_linux_amd64/bin/gh"
tar -czf "$scratch/gh_2.81.0_linux_amd64.tar.gz" -C "$scratch/archive" gh_2.81.0_linux_amd64
if command -v sha256sum >/dev/null 2>&1; then
  digest="$(sha256sum "$scratch/gh_2.81.0_linux_amd64.tar.gz" | awk '{print $1}')"
else
  digest="$(shasum -a 256 "$scratch/gh_2.81.0_linux_amd64.tar.gz" | awk '{print $1}')"
fi
printf '%s  gh_2.81.0_linux_amd64.tar.gz\n' "$digest" > "$scratch/checksums"
printf '2.81.0\tlinux\tamd64\t%s\n' "$digest" > "$scratch/source/gh-release-digests.tsv"
export PATH="$scratch/bin:$PATH" REQUIRED=2.81.0 RUNNER_TEMP="$scratch/runtime"
export GITHUB_PATH="$scratch/github-path" OBS_COMPLETE="$scratch/complete"
export OBS_ARCHIVE="$scratch/gh_2.81.0_linux_amd64.tar.gz" OBS_CHECKSUMS="$scratch/checksums"
# Installed CLI: a current version must return; a stale one must reach installation.
cp "$scratch/version-producer" "$scratch/bin/gh"
for scenario in satisfied stale failed-producer; do
  : > "$GITHUB_PATH"; rm -f "$OBS_COMPLETE"
  export INSTALL_NAMESPACE="$scenario" OBS_ARCH=sparc64 OBS_VERSION=2.81.0 OBS_VERSION_EXIT=0
  [[ "$scenario" != stale ]] || OBS_VERSION=2.0.0
  [[ "$scenario" != failed-producer ]] || OBS_VERSION_EXIT=23
  rc=0
  bash "$scratch/source/ensure-gh-skill.sh" > "$scratch/result" 2>&1 || rc=$?
  [[ -e "$OBS_COMPLETE" ]] || fail "installed $scenario did not consume the complete version output"
  case "$scenario" in
    satisfied) if [[ "$rc" != 0 ]] || ! grep -q 'already supports' "$scratch/result"; then fail 'current CLI did not return normally'; fi ;;
    stale) if [[ "$rc" != 1 ]] || ! grep -q 'Unsupported arch' "$scratch/result"; then fail 'stale CLI did not require installation'; fi ;;
    failed-producer) [[ "$rc" == 23 ]] || fail 'plausible installed version concealed producer failure' ;;
  esac
  [[ ! -s "$GITHUB_PATH" && ! -e "$RUNNER_TEMP/$scenario/bin/gh" ]] || fail 'installed probe published an archive'
done
# Downloaded CLI: real archive/digest handling, fixed network fixtures and scoped verifier.
cat > "$scratch/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'skill --help') exit 1 ;;
  'attestation --help') exit 0 ;;
  "attestation verify "*" --repo cli/cli --signer-workflow cli/cli/.github/workflows/deployment.yml") touch "$OBS_ATTESTED" ;;
  *) exit 2 ;;
esac
GH
chmod +x "$scratch/bin/gh"
export OBS_ARCH=x86_64 OBS_ATTESTED="$scratch/attested"
for scenario in downloaded-satisfied downloaded-stale downloaded-failed; do
  : > "$GITHUB_PATH"; rm -f "$OBS_COMPLETE" "$OBS_ATTESTED"
  export INSTALL_NAMESPACE="$scenario" OBS_VERSION=2.81.0 OBS_VERSION_EXIT=0
  [[ "$scenario" != downloaded-stale ]] || OBS_VERSION=2.0.0
  [[ "$scenario" != downloaded-failed ]] || OBS_VERSION_EXIT=23
  rc=0
  bash "$scratch/source/ensure-gh-skill.sh" > "$scratch/result" 2>&1 || rc=$?
  [[ -e "$OBS_COMPLETE" && -e "$OBS_ATTESTED" ]] || fail "$scenario did not completely observe the verified candidate"
  case "$scenario" in
    downloaded-satisfied)
      [[ "$rc" == 0 && -x "$RUNNER_TEMP/$scenario/bin/gh" ]] || fail 'valid candidate was not installed'
      [[ "$(cat "$GITHUB_PATH")" == "$RUNNER_TEMP/$scenario/bin" ]] || fail 'valid candidate was not published once'
      ;;
    downloaded-stale)
      if [[ "$rc" != 1 ]] || ! grep -q 'older than the requested' "$scratch/result"; then fail 'older candidate was not rejected'; fi
      ;;
    downloaded-failed) [[ "$rc" == 23 ]] || fail 'plausible downloaded version concealed producer failure' ;;
  esac
  if [[ "$scenario" != downloaded-satisfied ]]; then
    [[ ! -s "$GITHUB_PATH" && ! -e "$RUNNER_TEMP/$scenario/bin/gh" ]] || fail 'rejected candidate reached publication'
  fi
done
printf 'GitHub CLI version observation: complete producers and failure boundaries passed\n'
