#!/usr/bin/env bash
# Execute the two job gates against event/branch/input fixtures, then break them
# deliberately to prove the matrix detects the original and adjacent regressions.
set -euo pipefail
workflow="${1:-.github/workflows/validate-go-project.yaml}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
yq -o=json '.' "$workflow" > "$tmp/workflow.json"
node - "$tmp/workflow.json" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const workflow = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const flag = 'maintenance-default-branch';

// This deliberately supports only the primitive comparisons, boolean groups and
// format call used by these gates. Reject unfamiliar syntax instead of claiming
// to implement GitHub's entire expression language. For these comparisons,
// case-folded strings + loose equality preserve GitHub's primitive semantics.
function evaluate(gate, fixture) {
  const values = {
    'needs.changes.outputs.go': fixture.go,
    'github.event_name': fixture.event,
    'github.ref': fixture.ref,
    [`inputs.${flag}`]: fixture.input ?? '',
  };
  let expression = gate.trim().replace(/^\$\{\{\s*|\s*\}\}$/g, '');
  expression = expression.replace(/format\('refs\/heads\/\{0\}',\s*github\.event\.repository\.default_branch\)/g,
    JSON.stringify(`refs/heads/${fixture.branch}`));
  for (const [key, value] of Object.entries(values)) {
    expression = expression.replaceAll(key, JSON.stringify(value));
  }
  expression = expression.replace(/'(?:[^']|'')*'|"(?:[^"\\]|\\.)*"/g, literal => {
    const value = literal.startsWith("'") ? literal.slice(1, -1).replaceAll("''", "'") : JSON.parse(literal);
    return JSON.stringify(value.toLowerCase());
  });
  const syntax = expression.replace(/"(?:[^"\\]|\\.)*"/g, 'true');
  assert.match(syntax, /^(?:true|false|\s|&&|\|\||==|!=|[()])*$/, 'unsupported gate syntax');
  return Boolean(Function(`"use strict"; return (${expression});`)());
}

const fixtures = [];
for (const branch of ['main', 'master', 'trunk']) {
  for (const input of [undefined, false, 'false', true, 'true', 'TRUE']) {
    for (const go of ['', 'false', 'true']) {
      for (const event of ['push', 'pull_request', 'merge_group', 'workflow_dispatch', 'schedule']) {
        for (const ref of [`refs/heads/${branch}`, 'refs/heads/feature', 'refs/tags/v1', 'refs/pull/12/merge']) {
          const onDefault = ref === `refs/heads/${branch}`;
          const optedIn = input === true || String(input).toLowerCase() === 'true';
          const defaultPush = event === 'push' && onDefault && optedIn;
          fixtures.push({branch, input, go, event, ref, expected: {
            tidy: go === 'true' && event !== 'merge_group' && (!onDefault || defaultPush),
            deadcode: go === 'true' && (event === 'pull_request' || defaultPush),
          }});
        }
      }
    }
  }
}

function verify(job, gate) {
  for (const fixture of fixtures) {
    assert.equal(evaluate(gate, fixture), fixture.expected[job],
      `${job}: ${JSON.stringify(fixture)}`);
  }
}
for (const job of ['tidy', 'deadcode']) {
  verify(job, workflow.jobs[job].if);
  console.log(`PASS: ${job}, ${fixtures.length} event/branch/input combinations`);
}
assert.equal(workflow.on.workflow_call.inputs[flag].type, 'boolean');
assert.equal(workflow.on.workflow_call.inputs[flag].default, false, 'new behavior must remain opt-in');
assert.ok(workflow.concurrency.group.includes(`inputs.${flag}`), 'both flag states must have distinct concurrency groups');

const mutations = [
  ['tidy', 'original main/master exclusions', "needs.changes.outputs.go == 'true' && github.ref != 'refs/heads/main' && github.ref != 'refs/heads/master' && github.event_name != 'merge_group'"],
  ['deadcode', 'original pull-request-only gate', "needs.changes.outputs.go == 'true' && github.event_name == 'pull_request'"],
];
for (const job of ['tidy', 'deadcode']) {
  const gate = workflow.jobs[job].if;
  mutations.push(
    [job, 'missing Go filter', gate.replace("needs.changes.outputs.go == 'true'", 'true')],
    [job, 'hard-coded main', gate.replaceAll("format('refs/heads/{0}', github.event.repository.default_branch)", "'refs/heads/main'")],
    [job, 'opt-in removed', gate.replaceAll(`inputs.${flag}`, 'true')],
    [job, 'string false treated as truthy', gate.replace(`(inputs.${flag} == true || inputs.${flag} == 'true')`, `(inputs.${flag} != '')`)],
    [job, 'wrong event in default arm', gate.replace("github.event_name == 'push'", "github.event_name == 'schedule'")],
  );
}
for (const [job, name, gate] of mutations) {
  assert.notEqual(gate, workflow.jobs[job].if, `${name}: mutation did not apply`);
  assert.throws(() => verify(job, gate), {name: 'AssertionError'}, `${job}: accepted ${name}`);
  console.log(`PASS: ${job} rejects ${name}`);
}
JS
