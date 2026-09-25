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
yq -o=json '.' "$root/.github/actions/prepare-fixes/action.yaml" >"$work/exporter.json"
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

function verify(name, prepareGate, uploadGate, composite) {
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
    let uploaded;
    if (composite) {
      const local = {
        'inputs.manual-workflow-fixes': String(evaluate(composite.with['manual-workflow-fixes'], values, 'success')),
        'inputs.upload-enabled': String(evaluate(composite.with['upload-enabled'], values, 'success')),
        'steps.prepare.outputs.changed': String(changed),
      };
      uploaded = prepare && evaluate(uploadGate, local, status);
      // A successful linter admits the composite, but preparation itself can
      // subsequently fail or be cancelled after emitting changed=true. Model
      // that status separately so the caller cannot hide a weakened child gate.
      if (prepare && status === 'success') {
        for (const exportStatus of ['success', 'failure', 'cancelled']) {
          const expected = exportStatus !== 'cancelled' && (exportStatus === 'success' || optedIn)
            && changed && eligible && !bots.includes(author) && !bots.includes(owner);
          assert.equal(evaluate(uploadGate, local, exportStatus), expected,
            `${name}/upload after exporter ${exportStatus}: ${JSON.stringify(fixture)}`);
        }
      }
    } else uploaded = evaluate(uploadGate, values, status);
    assert.equal(uploaded, expectedUpload, `${name}/upload: ${JSON.stringify(fixture)}`);
  }
}

const ci = JSON.parse(fs.readFileSync(`${directory}/ci.json`, 'utf8'));
const exporter = JSON.parse(fs.readFileSync(`${directory}/exporter.json`, 'utf8'));
const prepareStep = exporter.runs.steps.find(step => step.id === 'prepare');
assert.equal(prepareStep.env.FIXES_ARTIFACT, '${{ inputs.artifact-name }}');
for (const output of ['artifact-name', 'changed', 'manual-required']) {
  assert.equal(exporter.outputs[output].value, '${{ steps.prepare.outputs.' + output + ' }}');
}
const go = JSON.parse(fs.readFileSync(`${directory}/validate-go-project.json`, 'utf8'));
const exporterUpload = exporter.runs.steps.find(step => (step.uses || '').startsWith('actions/upload-artifact@'));
for (const lane of ['tidy', 'golangci-lint', 'lint']) {
  const steps = go.jobs[lane].steps;
  const index = steps.findIndex(step => step.id === 'fixes');
  const call = steps[index];
  const checkout = steps[index - 1];
  const readOnly = steps.find(step => (step.name || '').includes('(read-only mode)'));
  assert.equal(call.uses, './.devantler-tech-actions/.github/actions/prepare-fixes');
  assert.equal(call.with['artifact-name'], (lane === 'lint' ? 'megalinter' : lane) + '-fixes-${{ job.check_run_id }}');
  assert.ok((checkout.uses || '').startsWith('actions/checkout@'));
  assert.deepEqual(checkout.with, {
    repository: '${{ job.workflow_repository }}', ref: '${{ job.workflow_sha }}',
    path: '.devantler-tech-actions', 'persist-credentials': false,
    'sparse-checkout': '.github/actions/prepare-fixes',
  }, `${lane}: exporter must come from the workflow's exact commit without credentials`);
  assert.equal(checkout.if, call.if, `${lane}: checkout and exporter admission differ`);
  assert.equal(call.with.mode ?? exporter.inputs.mode.default, lane === 'lint' ? 'workflow' : 'ordinary');
  assert.equal(steps.filter(step => (step.uses || '').startsWith('actions/upload-artifact@')).length, 0,
    `${lane}: duplicate patch uploader`);
  const manual = lane === 'lint';
  for (const fixture of fixtures) {
    const {input, status, apply, event, fork, author, owner, changed} = fixture;
    const optedIn = manual && (input === true || String(input).toLowerCase() === 'true');
    const eligible = apply && event === 'pull_request' && !fork && !bots.includes(author) && !bots.includes(owner);
    const values = {
      'inputs.manual-workflow-fixes': input ?? '',
      'needs.changes.outputs.signed-fixes': String(apply), 'github.event_name': event,
      'github.event.pull_request.head.repo.fork': fork,
      'github.event.pull_request.user.login': author, 'inputs.pr-owner': owner,
    };
    // with values are expressions, not steps: they have no implicit status gate.
    const decision = evaluate(call.with['upload-enabled'], values, 'success');
    assert.equal(decision, eligible, `${lane}: upload eligibility`);
    const admitted = evaluate(call.if, values, status);
    assert.equal(admitted, status !== 'cancelled' && (status === 'success' || optedIn), `${lane}: admission`);
    const local = {
      'inputs.upload-enabled': String(decision), 'inputs.manual-workflow-fixes': String(optedIn),
      'steps.prepare.outputs.changed': String(changed),
    };
    for (const childStatus of ['success', 'failure', 'cancelled']) {
      assert.equal(admitted && evaluate(exporterUpload.if, local, childStatus),
        admitted && childStatus !== 'cancelled' && (childStatus === 'success' || optedIn) && changed && eligible,
        `${lane}: upload after ${childStatus}`);
    }
    for (const changedOutput of [String(changed), '']) {
      assert.equal(evaluate(readOnly.if, {
        'steps.fixes.outputs.changed': changedOutput, 'steps.fixes.outputs.upload-enabled': String(decision),
      }, status), status === 'success' && changedOutput === 'true' && !eligible, `${lane}: read-only failure`);
    }
  }
  console.log(`PASS: ${lane}, exact-commit wiring and ${fixtures.length} eligibility/read-only cases`);
}
for (const name of ['lint', 'validate-go-project']) {
  const workflow = JSON.parse(fs.readFileSync(`${directory}/${name}.json`, 'utf8'));
  const job = workflow.jobs.lint;
  const prepare = job.steps.find(step => step.id === 'fixes');
  const composite = prepare.uses ? prepare : undefined;
  const upload = (composite ? exporter.runs.steps : job.steps).find(step => (step.uses || '').startsWith('actions/upload-artifact@'));
  verify(name, prepare.if, upload.if, composite);
  assert.equal(workflow.on.workflow_call.inputs[flag].type, 'boolean');
  assert.equal(workflow.on.workflow_call.inputs[flag].default, false);
  assert.ok(workflow.concurrency.group.includes(`inputs.${flag}`));
  for (const input of [true, 'true', 'TRUE', '', false, 'false']) {
    assert.equal(evaluate(composite ? prepare.with[flag] : prepare.env.MANUAL_WORKFLOW_FIXES, {[`inputs.${flag}`]: input}, 'success'),
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
      const fragment = composite && step === 'upload' ? "!cancelled() && (success() || inputs.manual-workflow-fixes == 'true')" : recovery;
      const mutated = original.replace(fragment, replacement);
      assert.notEqual(mutated, original, `${name}/${step}: mutation did not apply`);
      assert.throws(() => verify(name, step === 'prepare' ? mutated : prepare.if, step === 'upload' ? mutated : upload.if, composite), error =>
        error.code === 'ERR_ASSERTION' && error.message.startsWith(`${name}/`), `${name}/${step}: accepted ${label} or failed for unrelated syntax`);
      console.log(`PASS: ${name}/${step} rejects ${label}`);
    }
  }
}
JS
