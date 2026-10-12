#!/usr/bin/env bash
# Exercise the actual workflow resolver with tracked disposable consumer modules.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
workflow="${1:-$root/.github/workflows/validate-go-project.yaml}"
yq -o=json '.' "$workflow" >"$work/workflow.json"
# Preserve the actual immutable producer, rather than inventing its old result.
git -C "$root" show ee2755420184ae3fc58368e928427a5ec3ba1de6:.github/workflows/validate-go-project.yaml >"$work/legacy.yaml"
yq -o=json '.' "$work/legacy.yaml" >"$work/legacy.json"
node --input-type=module - "$root" "$work" <<'JS'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const [source, scratch] = process.argv.slice(2);
const workflow = JSON.parse(fs.readFileSync(path.join(scratch, 'workflow.json')));
const legacy = JSON.parse(fs.readFileSync(path.join(scratch, 'legacy.json')));
let controls = 0;
function command(cmd, args, cwd, env = {}) {
  const result = spawnSync(cmd, args, {cwd, env: {...process.env, ...env}, encoding: 'utf8', timeout: cmd === 'go' ? 90000 : 20000});
  assert.ifError(result.error);
  return result;
}
function git(cwd, ...args) {
  const result = command('git', args, cwd);
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}
function fixture(name, modules, untracked = []) {
  const dir = path.join(scratch, name);
  fs.mkdirSync(dir);
  git(dir, 'init', '-q');
  for (const mod of [...modules, ...untracked]) {
    const moduleDir = path.dirname(path.join(dir, mod));
    fs.mkdirSync(moduleDir, {recursive: true});
    fs.writeFileSync(path.join(dir, mod), 'module example.test/fixture\n\ngo 1.25.0\n');
    fs.writeFileSync(path.join(moduleDir, 'probe.go'), 'package fixture\nfunc Value() int { return 7 }\n');
    fs.writeFileSync(path.join(moduleDir, 'probe_test.go'),
      'package fixture\nimport "testing"\nfunc TestValue(t *testing.T) { if Value() != 7 { t.Fatal("wrong value") } }\n');
    if (modules.includes(mod)) git(dir, 'add', '--', mod, path.relative(dir, path.join(moduleDir, 'probe.go')),
      path.relative(dir, path.join(moduleDir, 'probe_test.go')));
  }
  return dir;
}
const directExpr = "${{ toJSON(inputs) == '{}' && contains(github.workflow_ref, '/.github/workflows/validate-go-project.yaml@') }}";
function resolve(dir, input = '', direct = true, extraEnv = {}) {
  const step = workflow.jobs.changes.steps.find(s => s.id === 'module-directory');
  assert.ok(step, 'current workflow has no module resolver');
  assert.equal(step.shell, 'bash');
  assert.equal(step.if, undefined, 'resolution must not be optional');
  assert.equal(step['continue-on-error'] ?? false, false, 'resolution failures must block');
  assert.equal(step.env.MODULE_DIRECTORY, '${{ inputs.working-directory }}');
  assert.equal(step.env.DIRECT_REQUIRED_RUN, directExpr);
  const checkout = workflow.jobs.changes.steps.find(s => s.id === 'module-helper');
  assert.ok(checkout, 'missing immutable helper checkout');
  assert.equal(checkout.with.repository, '${{ job.workflow_repository }}');
  assert.equal(checkout.with.ref, '${{ job.workflow_sha }}');
  assert.equal(checkout.with['persist-credentials'], false);
  assert.equal(checkout.with.path, '.devantler-tech-go-module');
  assert.equal(checkout.with['sparse-checkout'], '.github/scripts/resolve-go-module.sh');
  assert.equal(checkout.with['sparse-checkout-cone-mode'], false);
  const helper = path.join(dir, '.devantler-tech-go-module/.github/scripts');
  fs.mkdirSync(helper, {recursive: true});
  fs.copyFileSync(path.join(source, '.github/scripts/resolve-go-module.sh'), path.join(helper, 'resolve-go-module.sh'));
  const output = path.join(scratch, `output-${controls++}`);
  fs.writeFileSync(output, '');
  const result = command('bash', ['-euo', 'pipefail', '-c', step.run], dir, {
    GITHUB_WORKSPACE: dir, GITHUB_OUTPUT: output, MODULE_DIRECTORY: input,
    DIRECT_REQUIRED_RUN: String(direct), RESOLVE_REQUIRED: 'true', ...extraEnv,
  });
  const bytes = fs.readFileSync(output, 'utf8');
  assert.equal(fs.existsSync(path.join(dir, '.devantler-tech-go-module')), false, 'resolver checkout remained in consumer workspace');
  if (result.status === 0) assert.match(bytes, /^module-directory=[A-Za-z0-9._/-]+\n$/, 'invalid or repeated output');
  else assert.equal(bytes, '', 'failed resolution published a directory');
  return {status: result.status, output: bytes.slice('module-directory='.length).trim(), stderr: result.stderr};
}
function expect(dir, input, direct, wanted, native = false) {
  const result = resolve(dir, input, direct);
  assert.equal(result.status, 0, result.stderr);
  const values = {
    "inputs.working-directory || '.'": input || '.',
    'needs.changes.outputs.module-directory': result.output,
  };
  const setup = workflow.jobs.tidy.steps.find(s => s.uses?.startsWith('actions/setup-go@'));
  const mod = setup.with['go-version-file'].replace(/\$\{\{ (.*?) \}\}/g, (_, expr) => {
    assert.ok(Object.hasOwn(values, expr), `unexpected module expression ${expr}`);
    return values[expr];
  });
  assert.equal(mod, `${wanted}/go.mod`, 'required workflow selected the wrong consumer module');
  assert.ok(fs.statSync(path.join(dir, mod)).isFile());
  if (native) {
    const actual = command('go', ['test', './...'], path.join(dir, wanted), {GOWORK: 'off', GOTOOLCHAIN: 'local'});
    assert.equal(actual.status, 0, actual.stderr);
    fs.writeFileSync(path.join(dir, wanted, 'probe.go'), 'package fixture\nfunc Value() int { return 8 }\n');
    const broken = command('go', ['test', './...'], path.join(dir, wanted), {GOWORK: 'off', GOTOOLCHAIN: 'local'});
    assert.notEqual(broken.status, 0, 'actual selected module did not reject its deliberate wrong result');
    assert.match(broken.stdout + broken.stderr, /wrong value/, 'failure was not the intended regression');
  }
}
expect(fixture('root', ['go.mod']), '', true, '.', true);
expect(fixture('explicit', ['server/go.mod', 'other/go.mod']), 'server', false, 'server', true);
expect(fixture('root-with-fixtures', ['go.mod', 'fixtures/go.mod']), '', true, '.');
const nested = fixture('nested', ['server/go.mod']);
const legacyValues = {"inputs.working-directory || '.'": '.'};
const legacyBinding = legacy.jobs.test.defaults.run['working-directory'];
const legacyDirectory = legacyBinding.replace(/\$\{\{ (.*?) \}\}/g, (_, expression) => {
  assert.ok(Object.hasOwn(legacyValues, expression), 'unexpected historical binding');
  return legacyValues[expression];
});
assert.equal(legacyDirectory, '.', 'historical producer no longer exhibits root selection');
const legacySetup = legacy.jobs.test.steps.find(s => s.uses?.startsWith('actions/setup-go@'));
const legacyVersionFile = legacySetup.with['go-version-file'].replace(/\$\{\{ (.*?) \}\}/g, (_, expression) => {
  assert.ok(Object.hasOwn(legacyValues, expression), 'unexpected historical toolchain binding');
  return legacyValues[expression];
});
assert.equal(legacyVersionFile, './go.mod');
assert.equal(fs.existsSync(path.join(nested, legacyVersionFile)), false, 'historical module manifest unexpectedly exists');
const legacyFailure = command('go', ['test', './...'], path.join(nested, legacyDirectory), {GOWORK: 'off', GOTOOLCHAIN: 'local'});
assert.notEqual(legacyFailure.status, 0, 'actual historical selection validated the nested-only consumer');
assert.match(legacyFailure.stdout + legacyFailure.stderr, /go.mod file not found|does not contain main module|cannot find main module/,
  'historical failure was not the missing root module');
expect(nested, '', true, 'server', true);
expect(fixture('deep', ['services/api/go.mod']), '', true, 'services/api');
expect(fixture('explicit-prefix', ['server/go.mod']), './server/', false, 'server');
expect(fixture('called-root', ['go.mod', 'server/go.mod']), '', false, '.');
function refuse(dir, input = '', direct = true, env = {}) {
  const result = resolve(dir, input, direct, env);
  assert.notEqual(result.status, 0, 'unsafe or ambiguous module selection was accepted');
}
refuse(fixture('absent', []));
refuse(fixture('untracked', [], ['server/go.mod']));
refuse(fixture('multiple', ['api/go.mod', 'worker/go.mod']));
refuse(fixture('called-default', ['server/go.mod']), '', false);
refuse(fixture('missing-explicit', ['server/go.mod']), 'missing', false);
for (const input of ['../outside', '/', '/tmp', 'server/../server', 'server//nested', 'server\ninjected=yes', 'server;true']) {
  refuse(fixture(`unsafe-input-${controls}`, ['server/go.mod']), input, false);
}
for (const filename of ['with space/go.mod', 'with\nnewline/go.mod', 'dollar$/go.mod']) {
  refuse(fixture(`unsafe-path-${controls}`, [filename]));
}
for (const mod of ['go.mod', 'server/go.mod']) {
  const dir = fixture(`missing-${controls}`, [mod, ...(mod === 'go.mod' ? ['server/go.mod'] : [])]);
  fs.unlinkSync(path.join(dir, mod));
  refuse(dir);
  const linked = fixture(`symlink-${controls}`, [mod]);
  fs.renameSync(path.join(linked, mod), path.join(linked, 'target'));
  fs.symlinkSync(path.relative(path.dirname(path.join(linked, mod)), path.join(linked, 'target')), path.join(linked, mod));
  git(linked, 'add', '--', mod);
  refuse(linked);
}
const escaped = fixture('ancestor-link', ['server/go.mod']);
fs.renameSync(path.join(escaped, 'server'), path.join(scratch, 'outside-module'));
fs.symlinkSync(path.join(scratch, 'outside-module'), path.join(escaped, 'server'));
refuse(escaped);
const failedRead = fixture('failed-git', ['server/go.mod']);
const bin = path.join(scratch, 'bin');
fs.mkdirSync(bin);
fs.writeFileSync(path.join(bin, 'git'), '#!/bin/sh\nexit 51\n', {mode: 0o755});
refuse(failedRead, '', true, {PATH: `${bin}:${process.env.PATH}`});
const partialRead = fixture('partial-git', ['server/go.mod', 'worker/go.mod']);
const realGit = command('which', ['git'], source).stdout.trim();
fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\nif [ "$1" = ls-files ]; then\n  "${realGit}" ls-files --stage -z -- server/go.mod\n  exit 51\nfi\nexec "${realGit}" "$@"\n`, {mode: 0o755});
refuse(partialRead, '', true, {PATH: `${bin}:${process.env.PATH}`});
const unterminated = fixture('unterminated-git', ['server/go.mod', 'worker/go.mod']);
fs.writeFileSync(path.join(bin, 'git'), `#!/bin/sh\nif [ "$1" = ls-files ]; then\n  "${realGit}" ls-files --stage -z -- server/go.mod\n  tail_record=$("${realGit}" ls-files --stage -- worker/go.mod) || exit $?\n  printf '%s' "$tail_record"\n  exit 0\nfi\nexec "${realGit}" "$@"\n`, {mode: 0o755});
refuse(unterminated, '', true, {PATH: `${bin}:${process.env.PATH}`});
// Nothing selected means no module verdict; non-Go pull-request skips remain skips.
const skipped = fixture('no-go-validation', []);
const skippedOutput = path.join(scratch, 'skipped-output');
fs.writeFileSync(skippedOutput, '');
const skippedStep = workflow.jobs.changes.steps.find(s => s.id === 'module-directory');
const skippedResult = command('bash', ['-euo', 'pipefail', '-c', skippedStep.run], skipped, {
  GITHUB_WORKSPACE: skipped, GITHUB_OUTPUT: skippedOutput, RESOLVE_REQUIRED: 'false',
});
assert.equal(skippedResult.status, 0, skippedResult.stderr);
assert.equal(fs.readFileSync(skippedOutput, 'utf8'), '');
const evaluate = (expr, values) => {
  let code = expr.replace(/^\s*\$\{\{\s*|\s*\}\}\s*$/g, '');
  for (const key of Object.keys(values).sort((a,b) => b.length - a.length)) {
    code = code.split(key).join(JSON.stringify(values[key]));
  }
  return Function(`"use strict"; return (${code});`)();
};
const scope = skippedStep.env.RESOLVE_REQUIRED;
for (const changed of ['go', 'govulncheck', 'lintable', 'none']) {
  for (const explicit of ['', 'server']) for (const defaultBranch of [false, true])
    for (const event of ['pull_request', 'push', 'workflow_dispatch'])
    for (const scan of [false, true, 'false', 'true']) for (const test of [false, true, 'false', 'true']) {
    const values = {
      'inputs.working-directory': explicit,
      'inputs.scan-default-branch': scan,
      'inputs.test-default-branch': test,
      'github.event_name': event,
      'steps.filter.outputs.go': changed === 'go' ? 'true' : 'false',
      'steps.filter.outputs.govulncheck': changed === 'govulncheck' ? 'true' : 'false',
      'steps.filter.outputs.lintable': changed === 'lintable' ? 'true' : 'false',
      "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)": defaultBranch,
    };
    const scanEnabled = scan === true || scan === 'true';
    const testEnabled = test === true || test === 'true';
    const wanted = explicit !== '' || changed === 'go' || changed === 'lintable'
      || (scanEnabled && ((changed === 'govulncheck' && event === 'pull_request') || defaultBranch))
      || (testEnabled && defaultBranch);
    assert.equal(evaluate(scope, values), wanted, 'selected validation lost its module resolver');
    assert.equal(evaluate(workflow.jobs.changes.steps.find(s => s.id === 'module-helper').if, values), wanted);
    assert.equal(evaluate(workflow.jobs.changes.steps.find(s => s.name === 'Reserve module helper checkout path').if, values), wanted);
  }
}
const resolved = '${{ needs.changes.outputs.module-directory }}';
assert.equal(workflow.jobs.changes.outputs['module-directory'], '${{ steps.module-directory.outputs.module-directory }}');
for (const id of ['tidy', 'golangci-lint', 'deadcode', 'govulncheck', 'lint', 'build', 'test', 'coverage']) {
  const job = workflow.jobs[id];
  assert.equal(job.defaults.run['working-directory'], resolved, `${id}: run directory differs`);
  for (const step of job.steps.filter(s => s.uses?.startsWith('actions/setup-go@'))) {
    assert.equal(step.with['go-version-file'], `${resolved}/go.mod`, `${id}: toolchain directory differs`);
  }
}
const lint = workflow.jobs.lint.steps.find(s => s.id === 'ml');
assert.equal(lint.env.DEFAULT_WORKSPACE, resolved);
const golangci = workflow.jobs['golangci-lint'].steps.find(s => s.id === 'golangci-lint');
assert.equal(golangci.with['working-directory'], resolved);
for (const step of workflow.jobs.govulncheck.steps.filter(s => s.with?.['work-dir'])) {
  assert.equal(step.with['work-dir'], resolved);
  assert.equal(step.with['go-version-file'], `${resolved}/go.mod`);
  assert.ok(step.with['allow-file'].includes('needs.changes.outputs.module-directory'));
}
assert.equal(workflow.jobs.coverage.steps.find(s => s.with?.label === 'code-coverage/go').with.file,
  `${resolved}/coverage.cobertura.xml`);
console.log(`PASS: immutable legacy root-selection failure, repaired native nested module, defect rejection and ${controls} resolver controls`);
JS
