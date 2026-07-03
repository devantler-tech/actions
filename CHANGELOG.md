# Changelog

## [8.0.2](https://github.com/devantler-tech/actions/compare/v8.0.1...v8.0.2) (2026-07-03)


### Bug Fixes

* **scan-for-todo-comments:** restore self-checkout for post-cleanup ([#437](https://github.com/devantler-tech/actions/issues/437)) ([6f07366](https://github.com/devantler-tech/actions/commit/6f07366d6367e420f129bf73b1d9bdc8b54525b3))

## [8.0.1](https://github.com/devantler-tech/actions/compare/v8.0.0...v8.0.1) (2026-07-03)


### Bug Fixes

* resolve first-party self-references at the same commit ([#427](https://github.com/devantler-tech/actions/issues/427)) ([96b8f82](https://github.com/devantler-tech/actions/commit/96b8f82c71f7837eed166f65b173019b164676c6))

## [8.0.0](https://github.com/devantler-tech/actions/compare/v7.1.3...v8.0.0) (2026-07-02)


### ⚠ BREAKING CHANGES

* remove the sync-github-labels composite action (superseded by declarative IssueLabels) ([#418](https://github.com/devantler-tech/actions/issues/418))

### Features

* remove the sync-github-labels composite action (superseded by declarative IssueLabels) ([#418](https://github.com/devantler-tech/actions/issues/418)) ([0d7ff03](https://github.com/devantler-tech/actions/commit/0d7ff030438799e3bb423a8649115ad2b36ee78f))

## [7.1.3](https://github.com/devantler-tech/actions/compare/v7.1.2...v7.1.3) (2026-06-30)


### Continuous Integration

* skip the suite on the release-commit push to dodge the self-pin tag race ([#412](https://github.com/devantler-tech/actions/issues/412)) ([91efa53](https://github.com/devantler-tech/actions/commit/91efa53fa80d71341e1546510316b18722da79f5))

## [7.1.2](https://github.com/devantler-tech/actions/compare/v7.1.1...v7.1.2) (2026-06-30)


### Bug Fixes

* **approve-pr,upsert-issue:** retry-harden unguarded gh network calls ([#405](https://github.com/devantler-tech/actions/issues/405)) ([7fe5fad](https://github.com/devantler-tech/actions/commit/7fe5fad50cfbf15b3c62f05aa73964d3022fb155))
* **enable-auto-merge-on-pr:** retry-harden the gh API/merge network calls ([#402](https://github.com/devantler-tech/actions/issues/402)) ([b0e24b5](https://github.com/devantler-tech/actions/commit/b0e24b53dfef88cbd1a2a22c7451454191bc4559)), closes [#401](https://github.com/devantler-tech/actions/issues/401)

## [7.1.1](https://github.com/devantler-tech/actions/compare/v7.1.0...v7.1.1) (2026-06-27)


### Bug Fixes

* **upsert-issue:** fail with a clear error when body-file is missing ([#385](https://github.com/devantler-tech/actions/issues/385)) ([aabeddb](https://github.com/devantler-tech/actions/commit/aabeddb5c8d5061b9454bdc32aec7a3724bca498))

## [7.1.0](https://github.com/devantler-tech/actions/compare/v7.0.0...v7.1.0) (2026-06-27)


### Features

* **diagnose-flux:** add shared composite action for Flux failure diagnostics ([#368](https://github.com/devantler-tech/actions/issues/368)) ([d59a53c](https://github.com/devantler-tech/actions/commit/d59a53caea9f54b2782c44ea3fc3ee2088b20012))

## [7.0.0](https://github.com/devantler-tech/actions/compare/v6.1.0...v7.0.0) (2026-06-26)


### ⚠ BREAKING CHANGES

* All callers referencing old file names, input names, output names, or secret keys must be updated.

### Features

* merge reusable-workflows into the actions repo ([#314](https://github.com/devantler-tech/actions/issues/314)) ([b282265](https://github.com/devantler-tech/actions/commit/b282265e912820d25dd90248d1b1a910a0b4ce94))


### Code Refactoring

* **approve-pr:** accept client-id, deprecate app-id input ([#290](https://github.com/devantler-tech/actions/issues/290)) ([555e27d](https://github.com/devantler-tech/actions/commit/555e27de34b0f0f6b5aacb6fd82f24251225acac))


### Continuous Integration

* add shared retry.sh and bound setup-ksail-cli network pulls ([#302](https://github.com/devantler-tech/actions/issues/302)) ([b2c1104](https://github.com/devantler-tech/actions/commit/b2c1104d8a0ce00a089e340d2f5937bcff54e348))
* bound gh-skill network pulls with shared retry helper ([#308](https://github.com/devantler-tech/actions/issues/308)) ([679f53b](https://github.com/devantler-tech/actions/commit/679f53b728468bc7e87087658394e66d7d4c8809))
* grant release-please the workflows scope for self-pin rewrites ([#337](https://github.com/devantler-tech/actions/issues/337)) ([ea68e2b](https://github.com/devantler-tech/actions/commit/ea68e2b38262a6b3a2c67a76996da63a6e8e7e82))
* guard ci.yaml test wiring and fix silently-ignored free-disk-space results ([#355](https://github.com/devantler-tech/actions/issues/355)) ([16239bb](https://github.com/devantler-tech/actions/commit/16239bb3b5174452d8d44b98ec26e9d244781dbe))
* skip CI suite and dependency-review on release-please PRs ([#359](https://github.com/devantler-tech/actions/issues/359)) ([7f215f7](https://github.com/devantler-tech/actions/commit/7f215f7816adbbbc6beaba5248c5b3f9a1b91dfa))
