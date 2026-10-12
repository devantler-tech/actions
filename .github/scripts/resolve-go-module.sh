#!/usr/bin/env bash
# Select a tracked module without executing consumer code or trusting partial Git output.
set -euo pipefail
export LC_ALL=C
fail() { printf '::error::Go module selection: %s\n' "$1" >&2; exit 2; }
requested=${MODULE_DIRECTORY:-}
direct=${DIRECT_REQUIRED_RUN:-false}
[[ "$direct" == true || "$direct" == false ]] || fail 'invalid invocation identity'
[[ -n "${GITHUB_WORKSPACE:-}" ]] || fail 'missing workspace'
cd -- "$GITHUB_WORKSPACE"
workspace="$(pwd -P)"
[[ "$(git rev-parse --show-toplevel)" == "$workspace" ]] || fail 'workspace is not the checkout root'
index="$(mktemp)"
trap 'rm -f -- "$index"' EXIT
if ! git ls-files --stage -z -- 'go.mod' '*/go.mod' >"$index"; then
  fail 'tracked module inventory is incomplete'
fi
paths=(); modes=(); stages=()
record=''
while IFS= read -r -d '' record; do
  [[ "$record" == *$'\t'* ]] || fail 'invalid tracked module record'
  metadata=${record%%$'\t'*}
  filename=${record#*$'\t'}
  [[ "$metadata" =~ ^([0-9]{6})\ ([0-9a-f]{40}|[0-9a-f]{64})\ ([0-3])$ ]] || fail 'invalid tracked module metadata'
  mode=${BASH_REMATCH[1]}; stage=${BASH_REMATCH[3]}
  [[ "$filename" == go.mod || "$filename" == */go.mod ]] || fail 'unexpected tracked module path'
  paths+=("$filename"); modes+=("$mode"); stages+=("$stage")
done <"$index"
[[ -z "$record" ]] || fail 'tracked module inventory has an unterminated record'
selected=''
if [[ -n "$requested" ]]; then
  [[ "$requested" != /* ]] || fail 'absolute module directory is not allowed'
  # Preserve the conventional ./ prefix and trailing slash, but never path traversal.
  requested=${requested#./}
  requested=${requested%/}
  [[ -n "$requested" ]] || requested='.'
  selected="$requested"
else
  # A workflow_call retains its root default. Only input-free required runs discover.
  for filename in "${paths[@]}"; do
    [[ "$filename" != go.mod ]] || selected='.'
  done
  if [[ -z "$selected" && "$direct" == true ]]; then
    [[ ${#paths[@]} == 1 ]] || fail 'expected one tracked module; set working-directory for multiple modules'
    selected=${paths[0]%/go.mod}
  fi
  [[ -n "$selected" ]] || selected='.'
fi
if [[ "$selected" != '.' ]]; then
  [[ "$selected" =~ ^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$ ]] || fail 'unsafe module directory'
  current="$workspace"
  IFS=/ read -r -a components <<<"$selected"
  for component in "${components[@]}"; do
    [[ "$component" != '.' && "$component" != '..' ]] || fail 'module path contains traversal'
    current="$current/$component"
    [[ ! -L "$current" && -d "$current" ]] || fail 'module directory is missing or linked'
  done
  wanted="$selected/go.mod"
else
  wanted=go.mod
fi
found=0
for ((i=0; i<${#paths[@]}; i++)); do
  [[ "${paths[i]}" == "$wanted" ]] || continue
  [[ "${modes[i]}" == 100644 || "${modes[i]}" == 100755 ]] || fail 'module manifest is not a tracked regular file'
  [[ "${stages[i]}" == 0 ]] || fail 'module manifest is conflicted'
  found=$((found + 1))
done
[[ "$found" == 1 ]] || fail 'selected module manifest is not uniquely tracked'
[[ -f "$wanted" && ! -L "$wanted" ]] || fail 'selected module manifest is missing or linked'
printf '%s\n' "$selected"
