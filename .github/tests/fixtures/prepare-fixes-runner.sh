#!/usr/bin/env bash
# GitHub runner integration fixture, copied outside the helper before it is removed.
set -euo pipefail
case "$1" in
  setup)
    git init --quiet
    git config user.name 'Fix exporter fixture'
    git config user.email 'fixture@example.invalid'
    git config commit.gpgsign false
    mkdir -p module .github/workflows
    printf 'before\n' > notes.txt
    printf 'module example.invalid/fixture\n' > module/go.mod
    printf 'name: Before\n' > .github/workflows/fixture.yaml
    git add -- notes.txt module .github/workflows/fixture.yaml
    git commit --quiet -m 'fixture base'
    git clone --quiet --no-local . "$RUNNER_TEMP/replay"
    if [ "$SCENARIO" != clean ]; then
      printf 'after\n' > notes.txt
      printf 'outside the nested Go module\n' > new-file.txt
      printf '\000\001\377' > binary.bin
      printf '#!/bin/sh\nexit 0\n' > executable.sh
      chmod +x executable.sh
      if [ "$MANUAL" = true ]; then
        printf 'name: After\n' > .github/workflows/fixture.yaml
      fi
      git add -- notes.txt new-file.txt binary.bin executable.sh .github/workflows/fixture.yaml
    fi
    git write-tree > "$RUNNER_TEMP/expected-tree"
    git read-tree HEAD
    if [ "$SCENARIO" = export-failure ]; then
      # Fail a late command after changed=true. The real inline action must
      # remain failed while preserving its opted-in complete manual patch.
      mkdir -p "$RUNNER_TEMP/git-wrapper"
      command -v git > "$RUNNER_TEMP/real-git"
      cat > "$RUNNER_TEMP/git-wrapper/git" <<'GIT'
#!/usr/bin/env bash
set -euo pipefail
if [ "$*" = 'diff --name-only --no-renames HEAD -- .github/workflows/' ]; then
  echo 'intentional fixture workflow inspection failure' >&2
  exit 42
fi
exec "$(cat "$RUNNER_TEMP/real-git")" "$@"
GIT
      chmod +x "$RUNNER_TEMP/git-wrapper/git"
      echo "$RUNNER_TEMP/git-wrapper" >> "$GITHUB_PATH"
    fi
    ;;
  verify)
    [ ! -e .devantler-tech-actions ]
    [ "$ACTUAL_ARTIFACT" = "$ARTIFACT" ]
    [ "$ACTUAL_ELIGIBLE" = "$UPLOAD" ]
    expected_changed=true
    [ "$SCENARIO" != clean ] || expected_changed=false
    [ "$ACTUAL_CHANGED" = "$expected_changed" ]
    if [ "$SCENARIO" = export-failure ]; then
      [ "$ACTUAL_OUTCOME" = failure ]
      [ -z "$ACTUAL_MANUAL" ]
    else
      [ "$ACTUAL_OUTCOME" = success ]
      [ "$ACTUAL_MANUAL" = "$MANUAL" ]
    fi
    expected_artifacts=0
    if [ "$UPLOAD" = true ] && [ "$expected_changed" = true ]; then
      expected_artifacts=1
      cmp "$RUNNER_TEMP/$ARTIFACT.patch" "$RUNNER_TEMP/download/$ARTIFACT.patch"
      git -C "$RUNNER_TEMP/replay" apply --index "$RUNNER_TEMP/download/$ARTIFACT.patch"
      [ "$(git -C "$RUNNER_TEMP/replay" write-tree)" = "$(cat "$RUNNER_TEMP/expected-tree")" ]
    fi
    # Check real artifact absence as well as successful transfers. A skipped
    # download alone cannot establish that the upload was suppressed.
    gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/artifacts" --paginate > "$RUNNER_TEMP/artifacts.json"
    count="$(jq -s --arg name "$ARTIFACT" '[.[].artifacts[] | select(.name == $name)] | length' "$RUNNER_TEMP/artifacts.json")"
    [ "$count" = "$expected_artifacts" ]
    printf 'PASS hosted fix exporter: %s; artifact count=%s; outcome=%s\n' "$SCENARIO" "$count" "$ACTUAL_OUTCOME"
    ;;
  *) echo 'unknown fixture phase' >&2; exit 1 ;;
esac
