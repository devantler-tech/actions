const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const path = require("node:path");
const { test } = require("node:test");
const { buildStrategy } = require("release-please/build/src/factory");
const { parseConventionalCommits } = require("release-please/build/src/commit");
const { TagName } = require("release-please/build/src/util/tag-name");

const root = path.resolve(__dirname, "../../..");
const config = JSON.parse(
  readFileSync(path.join(root, "release-please-config.json")),
);
const releaseConfig = config.packages["."];
const base = { tag: TagName.parse("v1.2.3"), sha: "a".repeat(40) };
const internalTypes = ["ci", "build", "refactor", "chore", "docs", "test"];

test("the tested engine is bound to the production action revision", () => {
  const fixture = require("./package.json");
  const workflow = readFileSync(
    path.join(root, ".github/workflows/active-release.yaml"),
    "utf8",
  );
  const action = workflow.match(
    /uses:\s+googleapis\/release-please-action@([a-f0-9]{40})\b/,
  );
  assert.ok(action, "Expected the pinned production Release Please action");
  assert.equal(
    action[1],
    fixture.releasePleaseAction,
    "Verify the bundled engine version when updating the release action",
  );
  assert.equal(
    require("release-please/package.json").version,
    fixture.devDependencies["release-please"],
  );
});

// Use the production parser, strategy, versioner, notes generator and file updaters.
// The SCM boundary exposes repository identity only: any attempted API access fails.
async function candidate(messages) {
  const github = new Proxy(
    { repository: { owner: "devantler-tech", repo: "actions" } },
    {
      get(target, key) {
        assert.ok(
          Object.hasOwn(target, key),
          `Unexpected GitHub access: ${String(key)}`,
        );
        return target[key];
      },
    },
  );
  const strategy = await buildStrategy({
    github,
    targetBranch: "main",
    releaseType: releaseConfig["release-type"],
    changelogSections: releaseConfig["changelog-sections"],
    includeComponentInTag: config["include-component-in-tag"],
  });
  const commits = messages.map((message, index) => ({
    message,
    sha: (index + 1).toString(16).padStart(40, "0"),
    files: ["fixture.txt"],
  }));
  return strategy.buildReleasePullRequest(
    parseConventionalCommits(commits),
    base,
  );
}

test("an empty history does not propose a release", async () => {
  assert.equal(await candidate([]), undefined);
});

for (const type of internalTypes) {
  test(`${type}-only history does not propose a release`, async () => {
    assert.equal(
      await candidate([`${type}(pipeline): internal maintenance`]),
      undefined,
    );
  });
}

test("mixed internal changes do not propose a release", async () => {
  assert.equal(
    await candidate(
      internalTypes.map((type) => `${type}: internal ${type} change`),
    ),
    undefined,
  );
});

for (const [message, expected] of [
  ["feat: add a workflow capability", "1.3.0"],
  ["fix: repair a workflow capability", "1.2.4"],
  ["perf: reduce workflow latency", "1.2.4"],
  ["feat!: replace a workflow input", "2.0.0"],
  [
    "fix: replace a workflow input\n\nBREAKING CHANGE: callers must use the new input",
    "2.0.0",
  ],
]) {
  test(`${message.split("\n")[0]} proposes ${expected}`, async () => {
    const release = await candidate([message]);
    assert.ok(release, "Expected a release candidate");
    assert.equal(release.version.toString(), expected);
    assert.match(release.body.toString(), /workflow/);
  });
}

for (const type of internalTypes) {
  for (const message of [
    `${type}!: replace a workflow input`,
    `${type}: replace a workflow input\n\nBREAKING CHANGE: callers must use the new input`,
  ]) {
    test(`hidden ${type} with ${message.includes("!") ? "!" : "a breaking footer"} still releases a major`, async () => {
      const release = await candidate([message]);
      assert.ok(release, "Hiding a section must not hide its breaking changes");
      assert.equal(release.version.toString(), "2.0.0");
      assert.match(release.body.toString(), /BREAKING CHANGES/);
      assert.match(release.body.toString(), /workflow input|new input/);
    });
  }
}

test("a later fix produces one patch candidate with internal entries omitted", async () => {
  const internal = internalTypes.map(
    (type) => `${type}: internal ${type} change`,
  );
  assert.equal(await candidate(internal), undefined);
  const release = await candidate([
    "fix: restore reliable release behavior",
    ...internal,
  ]);
  assert.ok(release);
  assert.equal(release.version.toString(), "1.2.4");
  assert.equal(release.title.toString(), "chore(main): release 1.2.4");
  assert.equal(release.headRefName, "release-please--branches--main");
  const notes = release.body.toString();
  assert.match(notes, /restore reliable release behavior/);
  assert.doesNotMatch(
    notes,
    /internal (ci|build|refactor|chore|docs|test) change/,
  );

  const version = release.updates.find(
    (update) => update.path === "version.txt",
  );
  assert.ok(version, "The candidate must update the shipped version file");
  assert.equal(version.updater.updateContent("1.2.3\n"), "1.2.4\n");
  const changelog = release.updates.find(
    (update) => update.path === "CHANGELOG.md",
  );
  assert.ok(changelog, "The candidate must update the changelog");
  const content = changelog.updater.updateContent(
    "# Changelog\n\n## 1.2.3\n\nExisting release\n",
  );
  assert.match(content, /1\.2\.4/);
  assert.match(content, /restore reliable release behavior/);
  assert.match(content, /Existing release/);
  assert.doesNotMatch(
    content,
    /internal (ci|build|refactor|chore|docs|test) change/,
  );
});
