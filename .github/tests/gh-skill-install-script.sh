#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
script="$repo_root/.scripts/gh-skill-install.sh"

fakebin=$(mktemp -d)
log=$(mktemp)
export FAKE_GH_LOG="$log"
trap 'rm -rf "$fakebin"; rm -f "$log"' EXIT

cat > "$fakebin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
  printf 'call:'
  for arg in "$@"; do
    printf ' <%s>' "$arg"
  done
  printf '\n'
} >> "$FAKE_GH_LOG"

case "${FAKE_GH_MODE:-already-installed}" in
  hard-fail)
    echo "could not fetch blob: HTTP 403: API rate limit exceeded for installation" >&2
    exit 42
    ;;
  success)
    echo "installed"
    exit 0
    ;;
esac

case " $* " in
  *" --force "*)
    echo "installed with force"
    ;;
  *)
    echo "skills already installed: git-commit (use --force to overwrite)" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fakebin/gh"

PATH="$fakebin:$PATH" bash "$script" github/awesome-copilot git-commit --agent github-copilot --scope project

if [ "$(grep -c '^call:' "$log")" -ne 2 ]; then
  echo "::error::expected gh to be called twice for already-installed recovery"
  cat "$log"
  exit 1
fi
if ! tail -n 1 "$log" | grep -q -- '--force'; then
  echo "::error::expected second gh call to add --force"
  cat "$log"
  exit 1
fi
echo "already-installed recovery adds --force"

: > "$log"
if FAKE_GH_MODE=hard-fail PATH="$fakebin:$PATH" \
  bash "$script" github/awesome-copilot git-commit --agent github-copilot --scope project; then
  status=0
else
  status=$?
fi

if [ "$status" -ne 42 ]; then
  echo "::error::expected hard failure status 42, got $status"
  exit 1
fi
if [ "$(grep -c '^call:' "$log")" -ne 1 ]; then
  echo "::error::expected hard failure to avoid force retry"
  cat "$log"
  exit 1
fi
echo "non-idempotency failures keep their original exit status"

: > "$log"
FAKE_GH_MODE=success PATH="$fakebin:$PATH" \
  bash "$script" github/awesome-copilot git-commit --agent github-copilot --scope project

if [ "$(grep -c '^call:' "$log")" -ne 1 ]; then
  echo "::error::expected successful install to call gh once"
  cat "$log"
  exit 1
fi
if grep -q -- '--force' "$log"; then
  echo "::error::expected successful install to avoid --force"
  cat "$log"
  exit 1
fi
echo "immediate success does not retry"
