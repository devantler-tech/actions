#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workflow="$repo_root/.github/workflows/create-release.yaml"
ci="$repo_root/.github/workflows/ci.yaml"

input_default="$(yq -r '.on.workflow_call.inputs."disable-issue-side-effects".default' "$workflow")"
input_type="$(yq -r '.on.workflow_call.inputs."disable-issue-side-effects".type' "$workflow")"
if [[ "$input_default" != "false" || "$input_type" != "boolean" ]]; then
  echo "create-release must keep issue-side-effect suppression opt-in" >&2
  exit 1
fi

release_run="$(
  yq -r '.jobs.release.steps[] | select(.name == "🎉 Release") | .run' "$workflow"
)"
expected_run="npx semantic-release@25.0.3 \${{ inputs.disable-issue-side-effects && '--success false --fail false' || '' }} \${{ inputs.dry-run && '--dry-run' || '' }}"
if [[ "$release_run" != "$expected_run" ]]; then
  echo "create-release must disable semantic-release success and fail hooks when opted in" >&2
  exit 1
fi

contents_permission="$(
  yq -r '.jobs.release.steps[] | select(.id == "app-token") | .with."permission-contents"' "$workflow"
)"
if [[ "$contents_permission" != "write" ]]; then
  echo "create-release must retain contents:write for tags and releases" >&2
  exit 1
fi

issues_permission="$(
  yq -r '.jobs.release.steps[] | select(.id == "app-token") | .with."permission-issues"' "$workflow"
)"
prs_permission="$(
  yq -r '.jobs.release.steps[] | select(.id == "app-token") | .with."permission-pull-requests"' "$workflow"
)"
expected_issues="\${{ !inputs.disable-issue-side-effects && 'write' || '' }}"
if [[ "$issues_permission" != "$expected_issues" || "$prs_permission" != "$expected_issues" ]]; then
  echo "create-release must drop issue and pull-request write access only when opted in" >&2
  exit 1
fi

off_state="$(yq -r '.jobs."test-create-release".with."disable-issue-side-effects" // "unset"' "$ci")"
on_state="$(yq -r '.jobs."test-create-release-no-issue-side-effects".with."disable-issue-side-effects"' "$ci")"
if [[ "$off_state" != "unset" || "$on_state" != "true" ]]; then
  echo "create-release CI must exercise the default and opted-in states" >&2
  exit 1
fi

align_default="$(yq -r '.on.workflow_call.inputs."align-npm-with-consumer-contract".default' "$workflow")"
align_type="$(yq -r '.on.workflow_call.inputs."align-npm-with-consumer-contract".type' "$workflow")"
align_if="$(
  yq -r '.jobs.release.steps[] | select(.name == "📦 Align npm with consumer contract") | .if' \
    "$workflow"
)"
align_off="$(yq -r '.jobs."test-create-release".with."align-npm-with-consumer-contract" // "unset"' "$ci")"
align_on="$(yq -r '.jobs."test-create-release-no-issue-side-effects".with."align-npm-with-consumer-contract"' "$ci")"
if [[ "$align_default" != "false" || "$align_type" != "boolean" \
   || "$align_if" != '${{ inputs.align-npm-with-consumer-contract }}' \
   || "$align_off" != "unset" || "$align_on" != "true" ]]; then
  echo "create-release must keep npm alignment opt-in and exercise both rollout states" >&2
  exit 1
fi

align_npm_run="$(
  yq -r '.jobs.release.steps[] | select(.name == "📦 Align npm with consumer contract") | .run' "$workflow"
)"
if [[ -z "$align_npm_run" || "$align_npm_run" == "null" ]]; then
  echo "create-release must align npm with the checked-out consumer contract" >&2
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin" "$tmp_dir/runner" "$tmp_dir/workspace"
cat > "$tmp_dir/bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$#" == 1 && "$1" == "--version" ]]; then
  cat "$RUNNER_TEMP/npm-version"
  exit 0
fi
if [[ "$#" == 3 && "$1" == "install" && "$2" == "--global" ]]; then
  case "$3" in
    npm@11) printf '%s\n' '11.6.2' > "$RUNNER_TEMP/npm-version" ;;
    npm@11.2.0) printf '%s\n' '11.2.0' > "$RUNNER_TEMP/npm-version" ;;
    *) exit 1 ;;
  esac
  printf '%s\n' "$3" >> "$RUNNER_TEMP/npm-installs"
  exit 0
fi
printf 'unexpected npm invocation: %q' "$1" >&2
printf ' %q' "${@:2}" >&2
printf '\n' >&2
exit 1
EOF
chmod +x "$tmp_dir/bin/npm"

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {
    "packageManager": {
      "name": "npm",
      "version": "^11.0.0",
      "onFail": "error"
    }
  }
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ "$(cat "$tmp_dir/runner/npm-installs")" != "npm@11" ]]; then
  echo "create-release must install the npm major required by devEngines" >&2
  exit 1
fi

rm -f "$tmp_dir/runner/npm-installs"
cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "packageManager": "npm@11.2.0",
  "devEngines": {"packageManager":{"name":"npm","version":"^11.0.0"}}
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ "$(cat "$tmp_dir/runner/npm-installs")" != "npm@11.2.0" ]]; then
  echo "create-release must resolve compatible packageManager and devEngines declarations" >&2
  exit 1
fi

rm -f "$tmp_dir/runner/npm-installs"
cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "packageManager": "npm@11.2.0+sha224.00000000000000000000000000000000000000000000000000000000",
  "devEngines": {"packageManager":{"name":"npm","version":"^11.0.0"}}
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
if (
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
); then
  echo "create-release must reject packageManager integrity hashes it cannot verify" >&2
  exit 1
fi

rm -f "$tmp_dir/runner/npm-installs"
cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {"packageManager":{"name":"npm","onFail":"error"}}
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must ignore a versionless npm devEngines declaration" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {"packageManager":[]}
}
EOF
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must treat an empty npm devEngines alternatives array as no constraint" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "packageManager": "npm@11.2.0",
  "devEngines": {
    "packageManager": [
      {"name":"npm"},
      {"name":"npm","version":"12.x","onFail":"error"}
    ]
  }
}
EOF
printf '%s\n' '11.2.0' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must count a versionless alternative as satisfied" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {
    "packageManager": [
      {"name":"npm","version":"10.x","onFail":"error"},
      {"name":"npm","version":"11.x","onFail":"error"}
    ]
  }
}
EOF
printf '%s\n' '11.6.2' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must accept a satisfied alternative npm devEngines entry" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {
    "packageManager": [
      {"name":"npm","version":"~10.0.0","onFail":"error"},
      {"name":"npm","version":"11.x","onFail":"error"}
    ]
  }
}
EOF
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must evaluate supported alternatives before rejecting a narrow one" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {
    "packageManager": [
      {"name":"npm","version":"12.x","onFail":"error"},
      {"name":"npm","version":"11.x","onFail":"warn"}
    ]
  }
}
EOF
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must preserve non-blocking alternatives when one is already satisfied" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "packageManager": "npm@10.9.9",
  "devEngines": {
    "packageManager": [
      {"name":"npm","version":"11.x","onFail":"error"},
      {"name":"npm","version":"12.x","onFail":"warn"}
    ]
  }
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must apply the final alternative's non-blocking policy" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {
    "packageManager": {"name":"npm","version":"11.x","onFail":"download"}
  }
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ "$(cat "$tmp_dir/runner/npm-installs")" != "npm@11" ]]; then
  echo "create-release must align npm for the download failure policy" >&2
  exit 1
fi

rm -f "$tmp_dir/runner/npm-installs"
cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {"packageManager":{"name":"npm","version":"12.0.0","onFail":"warn"}}
}
EOF
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must not turn warn-only npm preferences into release gates" >&2
  exit 1
fi

rm -f "$tmp_dir/runner/npm-installs"
cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "devEngines": {"packageManager":{"name":"npm","version":"11.2.0"}}
}
EOF
printf '%s\n' '10.9.9' > "$tmp_dir/runner/npm-version"
if (
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
); then
  echo "create-release must reject a narrow npm requirement it cannot enforce exactly" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "packageManager": "npm@11.0.0-beta.1",
  "devEngines": {"packageManager":{"name":"npm","version":"^11.0.0"}}
}
EOF
if (
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
); then
  echo "create-release must reject prerelease contracts it cannot compare semantically" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{"packageManager":"npm"}
EOF
if (
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
); then
  echo "create-release must reject malformed present npm packageManager declarations" >&2
  exit 1
fi

for malformed_dev_engines in \
  '{"devEngines":{"packageManager":{"name":"npm","version":null,"onFail":"error"}}}' \
  '{"devEngines":{"packageManager":{"name":"npm","version":"11.x","onFail":null}}}' \
  '{"devEngines":{"packageManager":"npm"}}' \
  '{"devEngines":{"packageManager":{"version":"11.x"}}}' \
  '{"devEngines":{"packageManager":{"name":"npm","version":"11.x","onFailure":"error"}}}'; do
  printf '%s\n' "$malformed_dev_engines" > "$tmp_dir/workspace/package.json"
  if (
    cd "$tmp_dir/workspace"
    env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
      RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
  ); then
    echo "create-release must reject malformed npm devEngines declarations" >&2
    exit 1
  fi
done

rm -f "$tmp_dir/runner/npm-installs"
cat > "$tmp_dir/workspace/package.json" <<'EOF'
{"name":"consumer-without-an-npm-contract"}
EOF
(
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
)
if [[ -e "$tmp_dir/runner/npm-installs" ]]; then
  echo "create-release must retain the bundled npm when the consumer declares no npm contract" >&2
  exit 1
fi

cat > "$tmp_dir/workspace/package.json" <<'EOF'
{
  "packageManager": "npm@10.9.9",
  "devEngines": {"packageManager":{"name":"npm","version":"^11.0.0"}}
}
EOF
if (
  cd "$tmp_dir/workspace"
  env PATH="$tmp_dir/bin:$PATH" GITHUB_WORKSPACE="$tmp_dir/workspace" \
    RUNNER_TEMP="$tmp_dir/runner" bash -c "$align_npm_run"
); then
  echo "create-release must reject contradictory npm contracts" >&2
  exit 1
fi

echo "semantic-release issue side effects are opt-in disabled at least privilege"
