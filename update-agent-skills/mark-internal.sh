#!/usr/bin/env bash
# Mark every SKILL.md under a directory `metadata.internal: true`, so skill-discovery tools that honour
# the flag (for example `npx skills`) do not offer vendored development skills as if the repository
# published them. `gh skill update` re-downloads a skill's whole SKILL.md whenever its upstream changes,
# so this runs after every update rather than once.
#
# A SKILL.md that already carries the flag is left byte-identical. A SKILL.md with no frontmatter is not
# a discoverable skill and is skipped with a warning. Frontmatter that cannot be parsed or updated fails
# the run, because silently skipping it would leave that skill discoverable.
#
# Usage: mark-internal.sh <dir>
set -euo pipefail

dir=${1:-}
if [[ -z "$dir" || ! -d "$dir" ]]; then
  echo "::error::Directory not found: ${dir:-<empty>}"
  exit 1
fi

if ! yq --help 2>/dev/null | grep -q -- '--front-matter'; then
  echo "::error::mikefarah yq v4 with --front-matter support is required on PATH to mark skills internal."
  exit 1
fi

status=0
while IFS= read -r -d '' md; do
  if [[ "$(head -n 1 "$md")" != "---" ]]; then
    echo "::warning::Skipping $md: no frontmatter, so it is not a discoverable skill."
    continue
  fi

  if ! current=$(yq --front-matter=extract '.metadata.internal' "$md" 2>&1); then
    echo "::error::Cannot read the frontmatter of $md: $current"
    status=1
    continue
  fi
  if [[ "$current" == "true" ]]; then
    continue
  fi

  # Keep the file's own indentation (gh skill writes 4 spaces) so the diff is the one added line.
  indent=$(awk 'NR==1{next} /^---$/{exit} match($0, /^ +[^ ]/){print RLENGTH-1; exit}' "$md")
  if ! err=$(yq -i -I "${indent:-2}" --front-matter=process '.metadata.internal = true' "$md" 2>&1); then
    echo "::error::Cannot mark $md internal: $err"
    status=1
    continue
  fi
  echo "Marked internal: $md"
done < <(find "$dir" -type f -name SKILL.md -print0 | sort -z)

exit "$status"
