#!/usr/bin/env bash
# Check each reusable workflow's inputs and secrets in its own README section.
# Dependencies: Mike Farah yq v4, jq, awk (the same tools used by CI's parity checks).
set -euo pipefail
[[ $# -le 1 ]] || { echo 'Usage: check-workflow-readme.sh [repository-root]' >&2; exit 2; }
cd "${1:-.}"
[[ -f README.md && -d .github/workflows ]] || {
  echo 'Cannot check workflow documentation: README.md or .github/workflows is missing.' >&2
  exit 2
}
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
workflows=0
declarations=0
shopt -s nullglob
files=(.github/workflows/*.yaml .github/workflows/*.yml)
[[ ${#files[@]} -gt 0 ]] || { echo 'No workflow files found.' >&2; exit 2; }
for workflow in "${files[@]}"; do
  # Never turn failed YAML parsing, multiple documents, or a malformed interface into
  # an empty set of declarations and a successful check.
  if ! yq -o=json -I=0 '.' "$workflow" > "$tmp/workflow.json" ||
    ! jq -se 'length == 1 and (.[0] | type == "object")' "$tmp/workflow.json" > /dev/null; then
    echo "Cannot parse a single workflow mapping: $workflow" >&2
    exit 2
  fi
  if ! jq -e '(.on | type == "object") and (.on | has("workflow_call"))' "$tmp/workflow.json" > /dev/null; then
    continue
  fi
  if ! jq -e '.on.workflow_call | . == null or
      (type == "object" and (.inputs | . == null or type == "object") and
       (.secrets | . == null or type == "object"))' "$tmp/workflow.json" > /dev/null; then
    echo "Invalid workflow_call inputs/secrets mapping: $workflow" >&2
    exit 2
  fi
  jq -r '.on.workflow_call | ((.inputs // {} | keys[]) as $key | ["input", $key]),
      ((.secrets // {} | keys[]) as $key | ["secret", $key]) | @tsv' \
    "$tmp/workflow.json" > "$tmp/declared"
  workflows=$((workflows + 1))
  [[ -s "$tmp/declared" ]] || continue

  # A level-three section is bound by its workflow-file link. Only real table rows
  # below an interface heading count; examples, prose and other workflows cannot
  # accidentally document a missing input with the same name.
  if ! awk -v workflow="$workflow" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
    function flush() {
      if (selected) { sections++; printf "%s", rows }
      selected=0; rows=""; mode=""; table=0; header=0
    }
    {
      line=$0; sub(/\r$/, "", line)
      fenceLine=line; sub(/^[ ]*/, "", fenceLine)
      if (fence != "") {
        closing=fenceLine; sub(/[ \t]+$/, "", closing)
        if (length(closing) >= length(fence) &&
            ((substr(fence, 1, 1) == "`" && closing ~ /^`+$/) ||
             (substr(fence, 1, 1) == "~" && closing ~ /^~+$/))) fence=""
        next
      }
      if (comment) {
        end=index(line, "-->"); if (!end) next
        line=substr(line, end+3); comment=0
      }
      while (start=index(line, "<!--")) {
        before=substr(line, 1, start-1); after=substr(line, start+4)
        end=index(after, "-->")
        if (!end) { line=before; comment=1; break }
        line=before substr(after, end+3)
      }
      fenceLine=line; sub(/^[ ]*/, "", fenceLine)
      if (fenceLine ~ /^```/ || fenceLine ~ /^~~~/) {
        match(fenceLine, /^`+|^~+/); fence=substr(fenceLine, 1, RLENGTH); next
      }
      if (line ~ /^#{1,3} /) { flush(); inSection=(line ~ /^### /) }
      if (!inSection) next
      if (index(line, "](" workflow ")") > 0) selected=1
      if (line ~ /^#### /) {
        mode=""; table=0; header=0
        if (line ~ /^#### Inputs[ \t]*$/) mode="input"
        if (line ~ /^#### Secrets[ \t]*$/) mode="secret"
        if (line ~ /^#### Secrets and Inputs[ \t]*$/) mode="mixed"
        next
      }
      if (mode == "") next
      if (line !~ /^\|/) { table=0; header=0; next }
      split(line, cells, "|"); name=trim(cells[2]); kind=mode
      if (name == "Key" || name == "Name") { header=1; table=0; next }
      if (header && line ~ /^\|[-:| \t]+\|[ \t]*$/) { table=1; header=0; next }
      header=0
      if (!table) next
      if (name !~ /^`[A-Za-z_][A-Za-z0-9_-]*`$/) next
      name=substr(name, 2, length(name)-2)
      if (mode == "mixed") {
        type=trim(cells[3]); kind=""
        if (type ~ /^Input([ \t(]|$)/) kind="input"
        if (type == "Secret") kind="secret"
      }
      if (kind != "") rows=rows kind "\t" name "\n"
    }
    END { flush(); if (sections != 1) exit 1 }
  ' README.md > "$tmp/documented"; then
    echo "$workflow: add exactly one level-three README section linked to this workflow." >&2
    failures=$((failures + 1))
    continue
  fi
  while IFS=$'\t' read -r kind name; do
    declarations=$((declarations + 1))
    if ! grep -Fxq "$kind"$'\t'"$name" "$tmp/documented"; then
      echo "$workflow: $kind '$name' is undocumented. Add its row to this workflow's Secrets and Inputs table in README.md." >&2
      failures=$((failures + 1))
    fi
  done < "$tmp/declared"
done
[[ "$workflows" -gt 0 ]] || { echo 'No reusable workflows found.' >&2; exit 2; }
[[ "$failures" == 0 ]] || exit 1
echo "Workflow README parity OK: $declarations inputs/secrets across $workflows reusable workflows."
