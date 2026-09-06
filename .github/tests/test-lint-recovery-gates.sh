#!/usr/bin/env bash
# Exercise the actual recovery conditions, including GitHub's implicit success()
# rule, so a linter failure cannot silently discard an opted-in manual patch.
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for workflow in lint validate-go-project ci; do
  yq -o=json '.' "$root/.github/workflows/$workflow.yaml" >"$work/$workflow.json"
done
node - "$work" <<'JS'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const directory = process.argv[2];
const flag = 'manual-workflow-fixes';
const recovery = "!cancelled() && (success() || inputs.manual-workflow-fixes == true || inputs.manual-workflow-fixes == 'true')";
const bots = ['dependabot[bot]', 'dependabot', 'renovate[bot]', 'renovatebot', 'renovate'];

// Interpret only these gates' primitive comparisons and status functions. Unknown
// syntax fails instead of being executed. GitHub adds success() when no status
// function is present: https://docs.github.com/en/actions/reference/workflows-and-actions/expressions#status-check-functions
function evaluate(gate, values, status) {
  let expression = String(gate || 'true').trim().replace(/^\$\{\{\s*|\s*\}\}$/g, '');
  const explicitStatus = /\b(?:success|failure|cancelled|always)\s*\(/.test(expression);
  expression = expression.replace(/contains\(fromJSON\('([^']+)'\),\s*([^)]+)\)/g, (_, json, key) => {
    assert.ok(Object.hasOwn(values, key.trim()), `unknown context: ${key}`);
    return String(JSON.parse(json).map(value => value.toLowerCase()).includes(String(values[key.trim()]).toLowerCase()));
  });
  for (const [key, value] of Object.entries(values)) expression = expression.replaceAll(key, JSON.stringify(value));
  for (const [name, value] of Object.entries({success: status === 'success', failure: status === 'failure', cancelled: status === 'cancelled', always: true})) {
    expression = expression.replaceAll(`${name}()`, String(value));
  }
  expression = expression.replace(/'(?:[^']|'')*'|"(?:[^"\\]|\\.)*"/g, literal => {
    const value = literal.startsWith("'") ? literal.slice(1, -1).replaceAll("''", "'") : JSON.parse(literal);
    return JSON.stringify(value.toLowerCase());
  });
  const syntax = expression.replace(/"(?:[^"\\]|\\.)*"/g, 'true');
  assert.match(syntax, /^(?:true|false|\s|&&|\|\||==|!=|!|[()])*$/, 'unsupported recovery gate syntax');
  return (explicitStatus || status === 'success') && Boolean(Function(`"use strict"; return (${expression});`)());
}

const fixtures = [];
for (const input of [true, 'true', 'TRUE', undefined, false, 'false'])
for (const status of ['failure', 'success', 'cancelled'])
for (const apply of [true, false])
for (const event of ['pull_request', 'push', 'merge_group'])
for (const fork of [false, true])
for (const author of ['human', 'dependabot[bot]'])
for (const owner of ['human', 'renovate[bot]'])
for (const changed of [true, false]) {
  fixtures.push({input, status, apply, event, fork, author, owner, changed});
}

function verify(name, prepareGate, uploadGate) {
  for (const fixture of fixtures) {
    const {input, status, apply, event, fork, author, owner, changed} = fixture;
    const optedIn = input === true || String(input).toLowerCase() === 'true';
    const recoveryAllowed = status !== 'cancelled' && (status === 'success' || optedIn);
    const eligible = apply && event === 'pull_request' && !fork;
    const expectedPrepare = recoveryAllowed && (name !== 'lint' || eligible);
    const expectedUpload = recoveryAllowed && changed && (name === 'lint' || (eligible && !bots.includes(author) && !bots.includes(owner)));
    const values = {
      [`inputs.${flag}`]: input ?? '',
      'inputs.apply-fixes': apply,
      'needs.changes.outputs.signed-fixes': String(apply),
      'github.event_name': event,
      'github.event.pull_request.head.repo.fork': fork,
      'github.event.pull_request.user.login': author,
      'inputs.pr-owner': owner,
      'steps.fixes.outputs.changed': '',
    };
    const prepare = evaluate(prepareGate, values, status);
    assert.equal(prepare, expectedPrepare, `${name}/prepare: ${JSON.stringify(fixture)}`);
    // Check the upload boundary independently: an exporter can emit changed=true
    // before a later Git command fails, so outputs do not imply step success.
    values['steps.fixes.outputs.changed'] = String(changed);
    assert.equal(evaluate(uploadGate, values, status), expectedUpload, `${name}/upload: ${JSON.stringify(fixture)}`);
  }
}

const ci = JSON.parse(fs.readFileSync(`${directory}/ci.json`, 'utf8'));
for (const name of ['lint', 'validate-go-project']) {
  const workflow = JSON.parse(fs.readFileSync(`${directory}/${name}.json`, 'utf8'));
  const job = workflow.jobs.lint;
  const prepare = job.steps.find(step => step.id === 'fixes');
  const upload = job.steps.find(step => (step.uses || '').startsWith('actions/upload-artifact@'));
  verify(name, prepare.if, upload.if);
  assert.equal(workflow.on.workflow_call.inputs[flag].type, 'boolean');
  assert.equal(workflow.on.workflow_call.inputs[flag].default, false);
  assert.ok(workflow.concurrency.group.includes(`inputs.${flag}`));
  for (const input of [true, 'true', 'TRUE', '', false, 'false']) {
    assert.equal(evaluate(prepare.env.MANUAL_WORKFLOW_FIXES, {[`inputs.${flag}`]: input}, 'success'),
      input === true || String(input).toLowerCase() === 'true', `${name}: exporter flag normalization`);
  }
  const linter = job.steps.find(step => (step.uses || '').startsWith('oxsecurity/megalinter/'));
  assert.equal(linter['continue-on-error'] ?? false, false, 'lint errors must remain fatal');
  assert.equal(job['continue-on-error'] ?? false, false, 'job failure must remain fatal');
  const callers = Object.values(ci.jobs).filter(job => job.uses === `./.github/workflows/${name}.yaml`);
  assert.ok(callers.some(job => job.with?.[flag] === true), `${name}: missing opt-in caller`);
  assert.ok(callers.some(job => job.with?.[flag] === undefined || job.with[flag] === false), `${name}: missing default-off caller`);
  console.log(`PASS: ${name}, ${fixtures.length} recovery/status/authority cases`);

  for (const step of ['prepare', 'upload']) {
    const original = step === 'prepare' ? prepare.if : upload.if;
    for (const [label, replacement] of [['implicit success after lint failure', 'true'], ['ungated recovery', '!cancelled()'], ['cancelled recovery', "(success() || inputs.manual-workflow-fixes == true || inputs.manual-workflow-fixes == 'true')"]]) {
      const mutated = original.replace(recovery, replacement);
      assert.notEqual(mutated, original, `${name}/${step}: mutation did not apply`);
      assert.throws(() => verify(name, step === 'prepare' ? mutated : prepare.if, step === 'upload' ? mutated : upload.if), error =>
        error.code === 'ERR_ASSERTION' && error.message.startsWith(`${name}/`), `${name}/${step}: accepted ${label} or failed for unrelated syntax`);
      console.log(`PASS: ${name}/${step} rejects ${label}`);
    }
  }
}
JS
