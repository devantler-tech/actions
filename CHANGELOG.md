# Changelog

## [10.0.1](https://github.com/devantler-tech/actions/compare/v10.0.0...v10.0.1) (2026-07-15)


### Bug Fixes

* **validate-go-project:** raise govulncheck timeout to survive cold-cache scans ([#594](https://github.com/devantler-tech/actions/issues/594)) ([1f2a2fb](https://github.com/devantler-tech/actions/commit/1f2a2fba3e94120d6a17f6dea702d123c09af6b8))

## [10.0.0](https://github.com/devantler-tech/actions/compare/v9.0.12...v10.0.0) (2026-07-14)


### ⚠ BREAKING CHANGES

* remove the sync-github-labels composite action (superseded by declarative IssueLabels) ([#418](https://github.com/devantler-tech/actions/issues/418))
* All callers referencing old file names, input names, output names, or secret keys must be updated.
* **run-dotnet-tests:** run-dotnet-tests no longer accepts app-id or app-private-key inputs. Callers pinning by SHA are unaffected; on repin any still-passed values are simply ignored (unexpected-input warning).
* the `setup-copilot-skills`/`update-copilot-skills` action paths are removed and `setup-agent-skills`'s `agent` input is renamed to `agents`. Consumers on a pinned major (e.g. @v4) are unaffected until they bump; migration guides are in each action's README.
* the `codecov-token` input is removed from both actions. Callers must stop passing it (the reusable workflows are updated in lockstep).
* **copilot-skills:** `setup-copilot-skills` and `update-copilot-skills` both remove the `skills-lock` input; `setup-copilot-skills` also removes the `source` input and redefines `skills` as the sole list input. Delete any skills-lock.json and move each entry onto its own `<owner/repo> <skill>` line in `setup-copilot-skills.with.skills`.
* Action directories and input names have been renamed.

### Features

* add .NET project and test configurations ([#10](https://github.com/devantler-tech/actions/issues/10)) ([1ce56da](https://github.com/devantler-tech/actions/commit/1ce56da8d25676b7a9674b7c896f75e06da2caf1))
* add `require-checks-in-pr` composite action ([#113](https://github.com/devantler-tech/actions/issues/113)) ([1f66c91](https://github.com/devantler-tech/actions/commit/1f66c91d45d374ceac9fe830a783444ebc9be958))
* add auto-merge composite action for PRs ([#14](https://github.com/devantler-tech/actions/issues/14)) ([a8f34bd](https://github.com/devantler-tech/actions/commit/a8f34bd9d1876705e326007885beaa5f8c5901d0))
* add automation configuration for PR reviews and issue sessions ([f4b7152](https://github.com/devantler-tech/actions/commit/f4b7152947fd620413b3376039707ae46eaba6f0))
* add blocked label and update label sync configuration ([3041247](https://github.com/devantler-tech/actions/commit/3041247268b5f379c31e2d76e72fb4df2785791e))
* add Calculator class with basic arithmetic operations and corresponding unit tests ([f5c21a1](https://github.com/devantler-tech/actions/commit/f5c21a10dc535c6b57f0b4250b31c746b33f609b))
* add collapsible sections for workflow details in README ([2e8d0f9](https://github.com/devantler-tech/actions/commit/2e8d0f97c5d593034954b3aef61ca946f7adf506))
* add docs ([aba6c52](https://github.com/devantler-tech/actions/commit/aba6c52629877c30388ccdd51a42090a9e60ec6c))
* add dotnet-test-action for testing .NET solutions with GitHub Actions ([ad39d59](https://github.com/devantler-tech/actions/commit/ad39d59cd6526ed6863f4b3f5a6564235087d728))
* add EditorConfig file and update Calculator and CalculatorTests for consistency and clarity ([f032439](https://github.com/devantler-tech/actions/commit/f0324397fd2905cbe7b6a60833fe15eb2b803949))
* add GitHub workflows ([861d3e2](https://github.com/devantler-tech/actions/commit/861d3e2233ae32b5f4203e54e70971a2f018138b))
* add GitOps deployment workflow for managing Kubernetes resources ([f6f0ce7](https://github.com/devantler-tech/actions/commit/f6f0ce73c7c2938b829c6c76b4452421c8ad0c7d))
* add GitOps validation workflow ([8505da2](https://github.com/devantler-tech/actions/commit/8505da27affc0478bd012161782bfd2d27887c2e))
* add Hadolint action for linting Dockerfiles ([9f610a8](https://github.com/devantler-tech/actions/commit/9f610a89adae6fd6822da5461cc5e4044963d366))
* add Homebrew setup and environment initialization to GitOps workflows ([c4b0fe5](https://github.com/devantler-tech/actions/commit/c4b0fe5e636ab5b7f71067e3bc739fa7eb7dd9aa))
* add Homebrew setup step to GitOps workflows for consistent environment setup ([e300bd6](https://github.com/devantler-tech/actions/commit/e300bd64d259dce258cd8a8b1285e0cbcbbe04b0))
* add initial release configuration for semantic-release ([3c4f906](https://github.com/devantler-tech/actions/commit/3c4f906628c9abb2224ffbc661cc38a3e639f31f))
* add inputs for HOSTS_FILE and ROOT_CA_CERT_FILE in GitOps workflow ([6eefeeb](https://github.com/devantler-tech/actions/commit/6eefeeb6a085cf87afa7915911f7f9d4049797b5))
* add pull_request and merge_group triggers to Zizmor workflow ([1ce3f4b](https://github.com/devantler-tech/actions/commit/1ce3f4b21cdb1b5dfef7b8f629fe3335677d9618))
* add pull_request trigger to auto-merge and dotnet-test workflows ([63097da](https://github.com/devantler-tech/actions/commit/63097da91cc7f4dd04672119ec2094dfe0deeb4b))
* add pull_request trigger to GitOps lint and test workflows ([dbd5fe8](https://github.com/devantler-tech/actions/commit/dbd5fe80d87f05a00230b2b423f6b562b6726d6b))
* add released label to labels configuration ([a803193](https://github.com/devantler-tech/actions/commit/a803193ff0bec05a9d49ac6ae68df55c232cf20e))
* add Repo Assist labels to central config ([#161](https://github.com/devantler-tech/actions/issues/161)) ([b41fbfe](https://github.com/devantler-tech/actions/commit/b41fbfe687a0737a25ebe9ea749b95ad09c5c92e))
* add reusable workflow to sync upstream Kyverno policies and update README with usage instructions ([b119b9f](https://github.com/devantler-tech/actions/commit/b119b9fc03d4ca7cdff1b8ac64ee50034a267a88))
* add schedule trigger for sync labels workflow ([5f3527e](https://github.com/devantler-tech/actions/commit/5f3527e1928c288eaec633fcba8328489f5bdbe2))
* add shared workflows ([0fe78df](https://github.com/devantler-tech/actions/commit/0fe78df1a7408538ec22772ea019d777a9c82451))
* add step to append hosts file if it exists ([6f22cd1](https://github.com/devantler-tech/actions/commit/6f22cd124ad77fcf05101d631e57ba0d1ef3ae10))
* add upload-coverage action for GitHub Code Quality ([#170](https://github.com/devantler-tech/actions/issues/170)) ([60d895a](https://github.com/devantler-tech/actions/commit/60d895a7aabe6e3c0247c86a83560656a760ee08))
* add upsert-issue composite action ([#55](https://github.com/devantler-tech/actions/issues/55)) ([e3a0bd5](https://github.com/devantler-tech/actions/commit/e3a0bd51f2159079c77872080d493bc5ab9dc8bc))
* add VERSION_ARGS input to dotnet-embed-binaries workflow for version retrieval ([a648561](https://github.com/devantler-tech/actions/commit/a6485616ea76eb97174bc9ff388ee1f1b33cf69a))
* add workflow for cleaning up ghcr packages ([856fea4](https://github.com/devantler-tech/actions/commit/856fea4dbe245af4bfdc2016da174512e01ff9ca))
* add Zizmor composite action workflow ([c0b70d3](https://github.com/devantler-tech/actions/commit/c0b70d316dbb9ecba4b62a63a2fa77f2254b59b8))
* add Zizmor security analysis workflow and action documentation ([dbae7c7](https://github.com/devantler-tech/actions/commit/dbae7c74313bbec6b915fa9daadb3d425a3741de))
* add Zizmor workflow configuration ([6e1f9b5](https://github.com/devantler-tech/actions/commit/6e1f9b592bc7d79e2da668a40c2004e3d661376f))
* add Zizmor workflow configuration ([2b9e59f](https://github.com/devantler-tech/actions/commit/2b9e59fc9600d242bb6699debef21e87fdbee78e))
* add Zizmor workflow configuration ([5f1126b](https://github.com/devantler-tech/actions/commit/5f1126bd93fc1b942c676142fa16622fd88a1340))
* **cleanup-ghcr-packages:** add dry-run/package inputs and CI smoke test ([#193](https://github.com/devantler-tech/actions/issues/193)) ([1dddb9d](https://github.com/devantler-tech/actions/commit/1dddb9d8e7f448a5880d05695742b35960da5bb0))
* **copilot-skills:** drop lockfile, lean on gh skill frontmatter ([#95](https://github.com/devantler-tech/actions/issues/95)) ([7906319](https://github.com/devantler-tech/actions/commit/79063198d351a69bbd89369465004417ab01f173))
* **create-issues-from-todos:** support client-id, deprecate app-id ([#271](https://github.com/devantler-tech/actions/issues/271)) ([9d98cb8](https://github.com/devantler-tech/actions/commit/9d98cb8be059537ec1e82f71c90d75ecba321713))
* **dependency-review:** add composite for GitHub Dependency Review ([#217](https://github.com/devantler-tech/actions/issues/217)) ([21b2937](https://github.com/devantler-tech/actions/commit/21b29372cc10d4dedd8e78964c1f29742b970124))
* **diagnose-flux:** add shared composite action for Flux failure diagnostics ([#368](https://github.com/devantler-tech/actions/issues/368)) ([d59a53c](https://github.com/devantler-tech/actions/commit/d59a53caea9f54b2782c44ea3fc3ee2088b20012))
* **free-disk-space:** add composite action to reclaim runner disk ([#214](https://github.com/devantler-tech/actions/issues/214)) ([cbfd433](https://github.com/devantler-tech/actions/commit/cbfd433920d036c336b00b35af4c82f8e700affe))
* implement dotnet-test action with coverage reporting ([b4b4aac](https://github.com/devantler-tech/actions/commit/b4b4aac006abe7897239ab2e3877622fd27ca96b))
* merge reusable-workflows into the actions repo ([#314](https://github.com/devantler-tech/actions/issues/314)) ([b282265](https://github.com/devantler-tech/actions/commit/b282265e912820d25dd90248d1b1a910a0b4ce94))
* normalize secret input keys to UPPER_SNAKE_CASE ([#69](https://github.com/devantler-tech/actions/issues/69)) ([82ef4a7](https://github.com/devantler-tech/actions/commit/82ef4a7640f552468d56d1a142c4ad796faa2f6d))
* remove Codecov upload from coverage actions ([#175](https://github.com/devantler-tech/actions/issues/175)) ([7dbc3c3](https://github.com/devantler-tech/actions/commit/7dbc3c310c46eb51b0f298de2de0e2d9c6552eae))
* remove the sync-github-labels composite action (superseded by declarative IssueLabels) ([#418](https://github.com/devantler-tech/actions/issues/418)) ([0d7ff03](https://github.com/devantler-tech/actions/commit/0d7ff030438799e3bb423a8649115ad2b36ee78f))
* rename copilot-skills actions to agent-neutral agent-skills ([#178](https://github.com/devantler-tech/actions/issues/178)) ([3556694](https://github.com/devantler-tech/actions/commit/3556694b57702d81bfc5fb1d79a9ee0b4e53aca7))
* rename require-checks-in-pr to aggregate-job-checks ([#154](https://github.com/devantler-tech/actions/issues/154)) ([59d3ffb](https://github.com/devantler-tech/actions/commit/59d3ffbe1a9437fcc39e2794fa2f221abe878310))
* **run-dotnet-tests:** provision .NET 10 SDK alongside 9 ([#186](https://github.com/devantler-tech/actions/issues/186)) ([6916c45](https://github.com/devantler-tech/actions/commit/6916c45ed8dc22e62cb12f021480e29732d03575))
* **setup-copilot-skills:** add composite action to install gh skills ([#74](https://github.com/devantler-tech/actions/issues/74)) ([b35a193](https://github.com/devantler-tech/actions/commit/b35a1930f8bbba09bd6ea30fc9b49e9fbdb969a7))
* standardize actions with verb-purpose naming, add new actions and CI improvements ([#52](https://github.com/devantler-tech/actions/issues/52)) ([8d9a6d9](https://github.com/devantler-tech/actions/commit/8d9a6d91f094d4ce628381949f08c84632e7ac27))
* Update README and add new composite actions ([c401eac](https://github.com/devantler-tech/actions/commit/c401eaca053e4a385c4b59269c6e859df2599890))
* **update-copilot-skills:** auto-discover skill root directories ([#103](https://github.com/devantler-tech/actions/issues/103)) ([4489b81](https://github.com/devantler-tech/actions/commit/4489b810277f6c3ebbbe4626eee66e92e1a556e4))
* **update-copilot-skills:** pin resolved skill refs back into skills-lock.json ([#88](https://github.com/devantler-tech/actions/issues/88)) ([7c34831](https://github.com/devantler-tech/actions/commit/7c348311ff027f53036cbed500d5638511989310))
* upload .NET coverage to GitHub Code Quality ([#174](https://github.com/devantler-tech/actions/issues/174)) ([31d3c27](https://github.com/devantler-tech/actions/commit/31d3c2706ca08bb65fc26002d63a8483965b6570))


### Bug Fixes

* add checks to skip creation of OCI source and Kustomization if they already exist ([1fa3f17](https://github.com/devantler-tech/actions/commit/1fa3f17cf87dbea102184693c2c4726883bf17bd))
* add conditional check for Cilium installation in GitOps workflow ([e2857f0](https://github.com/devantler-tech/actions/commit/e2857f0cb5c669227b7e21d17e19f5106a669d40))
* add Copilot user to auto-merge condition ([cc639cb](https://github.com/devantler-tech/actions/commit/cc639cbd1f84fc614507f8441c824a944af37541))
* add dependency input for GitHub repo in dotnet-test workflow ([7ec8e76](https://github.com/devantler-tech/actions/commit/7ec8e76fa11c2422656b2f929861a388e7be45ad))
* add dependency on bootstrap job in deploy workflow ([eb8aee2](https://github.com/devantler-tech/actions/commit/eb8aee2be468b234f2c26d89399c737fb737855f))
* add deploy-dev job to handle deployment in GitOps workflow ([16d57d9](https://github.com/devantler-tech/actions/commit/16d57d9cf7f682a16b4d12fc7a5c3b9e6ab64556))
* add environment context to all jobs in gitops-deploy workflow ([29e3d6a](https://github.com/devantler-tech/actions/commit/29e3d6a330e7573963687f184755e318c1d46a3b))
* add GitHub Packages as NuGet source in dotnet-test workflow ([3c30545](https://github.com/devantler-tech/actions/commit/3c305458b32fb015f27deba1644412f4b9d01946))
* add merge_group event to auto-merge workflow ([0a18f95](https://github.com/devantler-tech/actions/commit/0a18f9501a7316084a4e544031cec75d70779778))
* add merge_group to GitOps test workflow ([c7063db](https://github.com/devantler-tech/actions/commit/c7063db2fe03e4248687c6e4a756b6ed598bd940))
* add merge_group to workflow triggers in dotnet-test and image-lint workflows ([57c8045](https://github.com/devantler-tech/actions/commit/57c80456b8ac78c8605d1a93da0d7a02ae595909))
* add merge_group trigger to GitOps validate workflow ([97a9e8c](https://github.com/devantler-tech/actions/commit/97a9e8c2c310491b356aed573dbf90ded409de05))
* add missing 'renovate[bot]' user login reference in auto-merge action workflow ([e2bd116](https://github.com/devantler-tech/actions/commit/e2bd11618534558a19a1903468a9f1ba5daf90db))
* add missing checkout step in reusable workflow for cluster bootstrap ([062dacb](https://github.com/devantler-tech/actions/commit/062dacbd315d0720a0eecc26398d67a9b4efc5cf))
* add missing connection in workflow diagram in README ([ea35790](https://github.com/devantler-tech/actions/commit/ea35790954508503d468b19f6a17e84631325d47))
* add missing continuation for cgroup.hostRoot setting in Cilium installation ([e362800](https://github.com/devantler-tech/actions/commit/e3628007bc048db3c46c2d6c3b979ca447b85efb))
* add missing wait flag for Cilium installation in GitOps workflow ([dadc93f](https://github.com/devantler-tech/actions/commit/dadc93f67f244af913232448ee44f14f29b74b6a))
* add mtls to cilium in bootstrap step ([e914ff3](https://github.com/devantler-tech/actions/commit/e914ff38416997457b8fae954cc8717863b67a1d))
* add permissions section for GitOps workflow ([675818e](https://github.com/devantler-tech/actions/commit/675818efda4dcfd9dec9e7250a6797b779935d0a))
* add push trigger for main branch in release workflow ([3fa15c1](https://github.com/devantler-tech/actions/commit/3fa15c1ec6af7d89d1e69e1bfb546936105cadef))
* add reusable TODOs workflow ([5d0d10c](https://github.com/devantler-tech/actions/commit/5d0d10ce1e8dca5b58accc8cfa07f14f15319c41))
* add suspend and resume commands for kustomization in reconcile step ([3d82e8d](https://github.com/devantler-tech/actions/commit/3d82e8dc55e52d1f8a1c1a6e24b5794721a3f859))
* add workflow_dispatch trigger to sync labels workflow ([531e764](https://github.com/devantler-tech/actions/commit/531e764ad02d5c4495b49141293e6589e9533b1c))
* address review feedback on `require-checks-in-pr` action ([#116](https://github.com/devantler-tech/actions/issues/116)) ([8fa6997](https://github.com/devantler-tech/actions/commit/8fa6997294452d1cf0982ff0925712a326c46c0c))
* allow 'devantler' to trigger auto-merge job ([7b8d8c9](https://github.com/devantler-tech/actions/commit/7b8d8c98f6c6d37221adc35e08f102ee68694810))
* allow NuGet push to continue on error ([5baba33](https://github.com/devantler-tech/actions/commit/5baba3319dd1e2d748dd7828ffa67c943db66b16))
* **approve-pr,upsert-issue:** retry-harden unguarded gh network calls ([#405](https://github.com/devantler-tech/actions/issues/405)) ([7fe5fad](https://github.com/devantler-tech/actions/commit/7fe5fad50cfbf15b3c62f05aa73964d3022fb155))
* **auto-merge:** fail closed on trusted-bot review gates ([#553](https://github.com/devantler-tech/actions/issues/553)) ([51ae69c](https://github.com/devantler-tech/actions/commit/51ae69cfa8f41023833719b313d3c21044f4ea60))
* **auto-merge:** harden mutable review evidence ([#575](https://github.com/devantler-tech/actions/issues/575)) ([9c8b35b](https://github.com/devantler-tech/actions/commit/9c8b35b0b25e661bc6f644b3a485e24eb1b8f25f))
* **auto-merge:** restrict privileged workflow to trusted bots ([#546](https://github.com/devantler-tech/actions/issues/546)) ([5a647d9](https://github.com/devantler-tech/actions/commit/5a647d98319fce3ee7abb7c9d9ed9e2870fccb52))
* **ci:** cache kubeconform schemas across Test/Coverage jobs ([#476](https://github.com/devantler-tech/actions/issues/476)) ([ee2354d](https://github.com/devantler-tech/actions/commit/ee2354d9a1bad3c2fe593d1282e177be9091a3be))
* correct condition syntax for dependency installation in dotnet-test workflow ([382545e](https://github.com/devantler-tech/actions/commit/382545ed462bfddd1bf31ecbc7ec1188b304cad0))
* correct emphasis on "Composite Action" in diagram ([865a142](https://github.com/devantler-tech/actions/commit/865a14280b732be27e42175b57e7159823c54dd6))
* correct formatting of auto-merge condition for consistency ([b0b8a4e](https://github.com/devantler-tech/actions/commit/b0b8a4ee422a6e87667221008a740d2a7c6e9c19))
* correct indentation in flux tag artifact command ([8710100](https://github.com/devantler-tech/actions/commit/87101008c8bff70b3d99f8a81bf7547b68a60305))
* correct syntax for dependency condition in dotnet-test workflow ([dd3795d](https://github.com/devantler-tech/actions/commit/dd3795d396a339d50cd32dcac883f99265fa486a))
* correct terminology in workflow diagram in README ([ce725cb](https://github.com/devantler-tech/actions/commit/ce725cb74f3c626668621b6ebeaba5a16c33236d))
* correct user login reference in auto-merge action workflow ([f11f256](https://github.com/devantler-tech/actions/commit/f11f256c8949820880c88451dca0a256c2d636e1))
* correct wording in README introduction for clarity ([17ebd8b](https://github.com/devantler-tech/actions/commit/17ebd8ba893a97c3f7e9d983d6401dcad961c8d2))
* **create-issues-from-todos:** avoid unpinned retry wrapper ([#518](https://github.com/devantler-tech/actions/issues/518)) ([9a54ed8](https://github.com/devantler-tech/actions/commit/9a54ed88f293d370ba22a3451965a206a176a845))
* **create-issues-from-todos:** preserve retry helper before checkout ([#523](https://github.com/devantler-tech/actions/issues/523)) ([be0a6cd](https://github.com/devantler-tech/actions/commit/be0a6cda17eabab73a2bf26a6519cf71bf358bb5))
* **create-issues-from-todos:** re-pin todo-to-issue-action to v5.1.15 ([#451](https://github.com/devantler-tech/actions/issues/451)) ([6415df0](https://github.com/devantler-tech/actions/commit/6415df0803ed03600ceb77f3725b678254469459)), closes [#222](https://github.com/devantler-tech/actions/issues/222)
* **create-issues-from-todos:** retry-harden raw.githubusercontent.com fetches ([#484](https://github.com/devantler-tech/actions/issues/484)) ([9a04d1a](https://github.com/devantler-tech/actions/commit/9a04d1aa581c6698bf4fb81ecdf0efe37102a49a)), closes [#483](https://github.com/devantler-tech/actions/issues/483)
* **create-issues-from-todos:** stop the action self-matching its own comment ([#457](https://github.com/devantler-tech/actions/issues/457)) ([5188832](https://github.com/devantler-tech/actions/commit/518883207726c973c00f15b138109daa1e27fba5))
* Delete .github/workflows/active-enable-auto-merge.yaml ([a533979](https://github.com/devantler-tech/actions/commit/a5339799d371b6952e7d3abdc9ea1ca096a28dfe))
* **deps:** update create-github-app-token action to v2.2.1 ([884a9b7](https://github.com/devantler-tech/actions/commit/884a9b7321e269351d5fc006d95e0b50b2ddedf6))
* disable kubeProxyReplacement in Cilium installation ([74e7ef8](https://github.com/devantler-tech/actions/commit/74e7ef8d4e4503295cfb55d2a6fcbf77f6709f07))
* enable Gateway API features in Cilium installation ([938ee58](https://github.com/devantler-tech/actions/commit/938ee5865b95bcc64631b4511d8ce618f2cf6df2))
* enable kubeProxyReplacement and set k8sServiceHost and k8sServicePort in Cilium installation ([cfb0fa0](https://github.com/devantler-tech/actions/commit/cfb0fa09089a80263d20af4ed37d3c04254d6433))
* **enable-auto-merge-on-pr:** retry-harden the gh API/merge network calls ([#402](https://github.com/devantler-tech/actions/issues/402)) ([b0e24b5](https://github.com/devantler-tech/actions/commit/b0e24b53dfef88cbd1a2a22c7451454191bc4559)), closes [#401](https://github.com/devantler-tech/actions/issues/401)
* enhance ksail update command with deployment tool specification ([d9515f6](https://github.com/devantler-tech/actions/commit/d9515f63d5640e448f278ab2a11e369acd705bd8))
* ensure token is passed during checkout step in auto-merge workflow ([8ac9c47](https://github.com/devantler-tech/actions/commit/8ac9c478218c1df17308c56b7bc18f37463843c7))
* **github-app:** update automation settings for PR review and remote control ([17691ce](https://github.com/devantler-tech/actions/commit/17691ce06f7c2324d7a41a60ec9cc3baf471bfea))
* **labels:** add roadmap to canonical label set so weekly sync stops deleting it ([#253](https://github.com/devantler-tech/actions/issues/253)) ([b31ec7b](https://github.com/devantler-tech/actions/commit/b31ec7baa4d7e9ca5b113f56cc928fe708872431))
* move Renovate configuration file ([a6290f7](https://github.com/devantler-tech/actions/commit/a6290f7afc77e94d2e2b5b4f2fd7046210ea7352))
* normalize action input names ([#72](https://github.com/devantler-tech/actions/issues/72)) ([961f62f](https://github.com/devantler-tech/actions/commit/961f62f4a771b31e48acaae4a619cef6c7fe2195))
* pass skills directory to gh skill update to fix write path ([#108](https://github.com/devantler-tech/actions/issues/108)) ([907b940](https://github.com/devantler-tech/actions/commit/907b9400e06b1ad77813d1200ba7945a2e329e00))
* refine condition for auto-merge job to include pull request event ([e018b2e](https://github.com/devantler-tech/actions/commit/e018b2e97916132f18d3eee1277e61ba52ae9900))
* remove deploy-dev job from GitOps test workflow ([bd7d1f2](https://github.com/devantler-tech/actions/commit/bd7d1f212bc5d70147112bc2bc410bf52134da9d))
* remove draft check from .NET test job ([b4316e1](https://github.com/devantler-tech/actions/commit/b4316e1a2dd3f04c6e6f8d1c1049082675e25895))
* remove forwardKubeDNSToHost setting from Cilium installation ([fc832f4](https://github.com/devantler-tech/actions/commit/fc832f490f4119b44aca760a0556f77e88fc7ee7))
* remove hardcoded project reference in todos.yaml ([c9cac8d](https://github.com/devantler-tech/actions/commit/c9cac8dbf9fb6439059b64a96fbb8b7d31439e4b))
* remove outdated README for zizmor-action ([9f610a8](https://github.com/devantler-tech/actions/commit/9f610a89adae6fd6822da5461cc5e4044963d366))
* remove PROJECTS_SECRET from todos.yaml ([8bfb9f8](https://github.com/devantler-tech/actions/commit/8bfb9f8c1d3439b144b7418cf59a9f7269fd9da0))
* remove unnecessary dependency on bootstrap job in push-to-oci ([dcf76df](https://github.com/devantler-tech/actions/commit/dcf76dfd2786ce60b778050985cf947f1198cf72))
* remove unused merge_group trigger from auto-merge workflow ([7698978](https://github.com/devantler-tech/actions/commit/76989782262d34128df91046f112d7e04f78c360))
* remove Zizmor Action and its documentation ([005c37f](https://github.com/devantler-tech/actions/commit/005c37f8ef5e1811388cf19b3b93eb721351b6be))
* rename job from auto-approve to auto-merge in workflow ([c24fbfb](https://github.com/devantler-tech/actions/commit/c24fbfb0186e2e122cc2976a914de7e956f68473))
* rename job from lint to validate in GitOps workflow ([5603f0e](https://github.com/devantler-tech/actions/commit/5603f0ec91ba2845c439f95d5fe200210127bc33))
* rename jobs in GitHub workflows for consistency ([625fd3b](https://github.com/devantler-tech/actions/commit/625fd3b150679c433ebd0dd351151f0aae6973ad))
* rename secret key to match reusable workflow definition ([#60](https://github.com/devantler-tech/actions/issues/60)) ([095e4c8](https://github.com/devantler-tech/actions/commit/095e4c8b58902168206ca3899b2ab9fbce9b1bcf))
* reorder checkout action in todos workflow ([391f482](https://github.com/devantler-tech/actions/commit/391f482cb718cdb35c8fb41cc6047571d4fbc7ca))
* replace Flux installation with KSail installation in deploy step ([41ab5a7](https://github.com/devantler-tech/actions/commit/41ab5a7b82564aec5a63190c1fc2b978a1ec016f))
* replace manual Homebrew installation with action for consistency across workflows ([0bb1e09](https://github.com/devantler-tech/actions/commit/0bb1e09f81280ee12233c50c6ff20282fbd10413))
* replace manual KSail installation with Homebrew for consistency across workflows ([505a5ce](https://github.com/devantler-tech/actions/commit/505a5cec16d888b02fbc3dd8478c16b831407e26))
* **require-checks-in-pr:** restore graceful handling of empty job-results ([#138](https://github.com/devantler-tech/actions/issues/138)) ([19f1f2e](https://github.com/devantler-tech/actions/commit/19f1f2e8c01aeafe037af8ca26d8c2dab1dee2a4))
* resolve first-party self-references at the same commit ([#427](https://github.com/devantler-tech/actions/issues/427)) ([96b8f82](https://github.com/devantler-tech/actions/commit/96b8f82c71f7837eed166f65b173019b164676c6))
* restore permissions for issues in todos.yaml ([b1f4c87](https://github.com/devantler-tech/actions/commit/b1f4c876a02ab7b2bded19d3b050ed67db98a818))
* **run-dotnet-tests:** gate coverage upload on runner.os, not the unavailable matrix context ([#241](https://github.com/devantler-tech/actions/issues/241)) ([8ce1952](https://github.com/devantler-tech/actions/commit/8ce19528eda1ef50f3d028b685c53aebaed6ae62))
* sanitize tag name for OCI artifact in deployment workflow ([61201e1](https://github.com/devantler-tech/actions/commit/61201e1099d9bac0f0ea60c0d200542618c5e26d))
* **scan-for-todo-comments:** restore self-checkout for post-cleanup ([#437](https://github.com/devantler-tech/actions/issues/437)) ([6f07366](https://github.com/devantler-tech/actions/commit/6f07366d6367e420f129bf73b1d9bdc8b54525b3))
* scope GitHub App tokens to least privilege (zizmor github-app) ([#279](https://github.com/devantler-tech/actions/issues/279)) ([40816ac](https://github.com/devantler-tech/actions/commit/40816acee2940a3b46bd5c042a023ee24528353b)), closes [#274](https://github.com/devantler-tech/actions/issues/274)
* set forwardKubeDNSToHost to false in Cilium installation ([48d3003](https://github.com/devantler-tech/actions/commit/48d30037de9edec6537339992fe8181c2a7c9ba3))
* **setup-agent-skills:** recover already-installed retries ([#513](https://github.com/devantler-tech/actions/issues/513)) ([290ff61](https://github.com/devantler-tech/actions/commit/290ff61ed7c929ddb744871810142210ba4428cc))
* **setup-copilot-skills:** default scope to repo for CI use ([#85](https://github.com/devantler-tech/actions/issues/85)) ([5383a2b](https://github.com/devantler-tech/actions/commit/5383a2b945b5776b0fc9299d182a2db382af352f))
* **setup-copilot-skills:** install gh on demand when runner has an older version ([#76](https://github.com/devantler-tech/actions/issues/76)) ([538d710](https://github.com/devantler-tech/actions/commit/538d7103ed24531647941b3a460393b5ac7ed756))
* **setup-ksail-cli:** trust first-party tap so brew can load the KSail Cask ([#262](https://github.com/devantler-tech/actions/issues/262)) ([7848ec0](https://github.com/devantler-tech/actions/commit/7848ec0b7adcfeaf4d50d8483c4da28adf378171))
* simplify auto-merge condition formatting for readability ([3f4f428](https://github.com/devantler-tech/actions/commit/3f4f428c7388c21bb27c56cda6502589a4654d68))
* simplify auto-merge condition formatting in workflow ([6b44303](https://github.com/devantler-tech/actions/commit/6b443031e1ae99ec27f7cc48a050591b2ab813af))
* simplify dependency installation condition in dotnet-test workflow ([e4171c4](https://github.com/devantler-tech/actions/commit/e4171c4c7bd37c8eec3861f90a61ba41f13334b9))
* specify version for reusable workflow in active-release.yaml ([b2d85ee](https://github.com/devantler-tech/actions/commit/b2d85eefa2d5a75ee53571910e29080c5bdd271a))
* **template-sync:** use app token for target pushes ([#585](https://github.com/devantler-tech/actions/issues/585)) ([023b103](https://github.com/devantler-tech/actions/commit/023b1035651486b96773522a7db057394dc49fd0))
* update action paths in workflow files to use local references ([44620f6](https://github.com/devantler-tech/actions/commit/44620f6c6e9bc2046c7959932fbd104a74d6b1a5))
* update action references to specific versions in multiple workflows ([d69de4b](https://github.com/devantler-tech/actions/commit/d69de4b313f789d5aff0bf42614da212fc5362e2))
* Update action.yaml ([f378f06](https://github.com/devantler-tech/actions/commit/f378f06c871bf640a57ec20466a4f54d38d35587))
* update actions/checkout to persist-credentials: false for improved security ([df6427f](https://github.com/devantler-tech/actions/commit/df6427f6e447c66e51243889e989e4a557fa13bb))
* update auto-merge condition formatting for clarity ([85a3844](https://github.com/devantler-tech/actions/commit/85a3844aa6c46d8459d37d0d90c22f6107195ff4))
* update auto-merge condition to exclude draft pull requests ([7ba542f](https://github.com/devantler-tech/actions/commit/7ba542fee6165e00949e49e2cab2ef42b98d5d4a))
* update auto-merge condition to exclude draft pull requests ([f6c779a](https://github.com/devantler-tech/actions/commit/f6c779a9be5a6ba8a831d98909d734f7af9127cc))
* update auto-merge workflow to use GitHub App Token for authentication ([f2b7abc](https://github.com/devantler-tech/actions/commit/f2b7abcc15f2e66bce8fb466059a9bc201365ca7))
* update auto-merge-action reference to specific commit for consistency ([b8298f5](https://github.com/devantler-tech/actions/commit/b8298f5d8bb6d8b1d807c22ec9847889b1471858))
* update condition for auto-merge job to use pull request user login ([b58c3a0](https://github.com/devantler-tech/actions/commit/b58c3a07e91dd91a5a39bc2108e88337805ca458))
* update dependency installation condition to use env variable ([8b28c8c](https://github.com/devantler-tech/actions/commit/8b28c8c3b4dc4f3512ef1ebb6637fef264cc1bc7))
* update diagram in README to accurately represent workflow relationships ([ff00c64](https://github.com/devantler-tech/actions/commit/ff00c64742b4f47d07a3ac8f2c4c47833e73e6f0))
* update dotnet-test action reference to use the latest version ([e146fe7](https://github.com/devantler-tech/actions/commit/e146fe7ecda9d78314d6378b0401d2ceaff370e1))
* update dotnet-test-action usage to local path ([74fdadf](https://github.com/devantler-tech/actions/commit/74fdadf32eb1b2a199e557f9ca92c4e0206a0c7b))
* update dotnet-test-action usage to local path and add working directory ([#13](https://github.com/devantler-tech/actions/issues/13)) ([3685954](https://github.com/devantler-tech/actions/commit/3685954ea951eff2f2b5e858ce8534e662b27237))
* update EndBug/label-sync action to specific commit for stability ([4c00454](https://github.com/devantler-tech/actions/commit/4c004547d1487bb0fd9e3801917c015eed52378a))
* update GitHub Actions relationship diagram for clarity and accuracy ([0df4ee9](https://github.com/devantler-tech/actions/commit/0df4ee9f2a1169c870bb5f8eea023674cdf4d2ea))
* update host and root CA file checks to use vars fallback ([b891ccc](https://github.com/devantler-tech/actions/commit/b891ccc71d7c324945e44b0476ad04173a90954d))
* update name of NuGet source step to reflect GHCR usage ([baaf98b](https://github.com/devantler-tech/actions/commit/baaf98b068289086e9b0fa3eab8aa2093fdbf7c1))
* update output setting for current Kubernetes context in reconcile step ([08a2df7](https://github.com/devantler-tech/actions/commit/08a2df782236b6eb0fa547e6d62c91af6c6f850e))
* update README to include links for reusable workflows and composite actions ([715aedf](https://github.com/devantler-tech/actions/commit/715aedfa4862b2673db46f6c0c72ab5783391f90))
* update reusable workflow callsites for naming refactor ([#53](https://github.com/devantler-tech/actions/issues/53)) ([73f2eb4](https://github.com/devantler-tech/actions/commit/73f2eb403e2337c84e704adb2fcea86b71ac438a))
* update workflow diagram to correct relationships and add missing connections ([88bed98](https://github.com/devantler-tech/actions/commit/88bed98480665836a301b340bdc35db1afa8e391))
* update workflow reference in active-release.yaml ([d4b23f9](https://github.com/devantler-tech/actions/commit/d4b23f9e20423712a3300a63bdbaf4ac70fee721))
* update zizmor action reference to specific commit for consistency ([3899a97](https://github.com/devantler-tech/actions/commit/3899a97c25519bda7685b665a7afd0064468f22f))
* update Zizmor workflow triggers to use workflow_call only ([9b0d3e7](https://github.com/devantler-tech/actions/commit/9b0d3e77f78a8de4d03006e9b860afebbab75207))
* **update-copilot-skills:** address post-merge review comments ([#92](https://github.com/devantler-tech/actions/issues/92)) ([bf04cc0](https://github.com/devantler-tech/actions/commit/bf04cc00fffcc37b573cdf045556f3f26fe9fe8c))
* **upsert-issue:** fail with a clear error when body-file is missing ([#385](https://github.com/devantler-tech/actions/issues/385)) ([aabeddb](https://github.com/devantler-tech/actions/commit/aabeddb5c8d5061b9454bdc32aec7a3724bca498))
* use UPPER_SNAKE_CASE for secret input keys ([#67](https://github.com/devantler-tech/actions/issues/67)) ([f99f6c9](https://github.com/devantler-tech/actions/commit/f99f6c990a696a8c8d48141ff04ea4244a763c20))
* **workflows:** revert step-security actions to original authors ([#134](https://github.com/devantler-tech/actions/issues/134)) ([5daa8b5](https://github.com/devantler-tech/actions/commit/5daa8b5b0b53c70ee24446ec76089515ec6cd6db))


### Code Refactoring

* **agent-skills:** share the gh bootstrap via one script ([#211](https://github.com/devantler-tech/actions/issues/211)) ([14c9fed](https://github.com/devantler-tech/actions/commit/14c9fed2dc9b005a16e2676114f51be0aad50b9e))
* **approve-pr:** accept client-id, deprecate app-id input ([#290](https://github.com/devantler-tech/actions/issues/290)) ([555e27d](https://github.com/devantler-tech/actions/commit/555e27de34b0f0f6b5aacb6fd82f24251225acac))
* consolidate test workflows into single ci.yaml ([#121](https://github.com/devantler-tech/actions/issues/121)) ([3b7af5b](https://github.com/devantler-tech/actions/commit/3b7af5b8d83a7c2ceb664ae7314444b9c6811c9f))
* remove workflow_dispatch and merge_group triggers from multiple workflows ([ba4dab8](https://github.com/devantler-tech/actions/commit/ba4dab84be72ffe0fabda52006a5a58dd3e68fc2))
* rename job in dotnet-embed-binaries workflow ([10ef47a](https://github.com/devantler-tech/actions/commit/10ef47a82d2473e5402fe0633ab8db1b9384a6b8))
* rename secret inputs to kebab-case ([#65](https://github.com/devantler-tech/actions/issues/65)) ([33461ab](https://github.com/devantler-tech/actions/commit/33461abe2a10a5375807204f3629d3e8fe9fa288))
* rename workflow for embedding binaries in .NET projects ([c084677](https://github.com/devantler-tech/actions/commit/c084677aad3aeb65425a2146dd9df1c5ba01fb14))
* replace inline status-check jobs with require-checks-in-pr action ([#118](https://github.com/devantler-tech/actions/issues/118)) ([e5a89fd](https://github.com/devantler-tech/actions/commit/e5a89fd767ca94e815d1dab2cd42cb7ee4e3d2e9))
* **run-dotnet-tests:** drop dead app-id/app-private-key inputs ([#264](https://github.com/devantler-tech/actions/issues/264)) ([0e12329](https://github.com/devantler-tech/actions/commit/0e1232924bf8b07a40b1b24e13e200744fbabcfa))
* split enable-auto-merge-on-pr into approve-pr and enable-auto-merge-on-pr ([#58](https://github.com/devantler-tech/actions/issues/58)) ([ba49255](https://github.com/devantler-tech/actions/commit/ba492559ea1bd82fdb0755e3e936dfa6db83be8f))


### Continuous Integration

* add enable-auto-merge workflow ([#110](https://github.com/devantler-tech/actions/issues/110)) ([ae7c660](https://github.com/devantler-tech/actions/commit/ae7c6604c9dcef5a17b20be9b52d533894597178))
* add README↔action.yaml input/output parity guard ([#197](https://github.com/devantler-tech/actions/issues/197)) ([6d8bcd6](https://github.com/devantler-tech/actions/commit/6d8bcd616576371b9ae9a17421dfed8a7ee5501b))
* add shared retry.sh and bound setup-ksail-cli network pulls ([#302](https://github.com/devantler-tech/actions/issues/302)) ([b2c1104](https://github.com/devantler-tech/actions/commit/b2c1104d8a0ce00a089e340d2f5937bcff54e348))
* bound gh-skill network pulls with shared retry helper ([#308](https://github.com/devantler-tech/actions/issues/308)) ([679f53b](https://github.com/devantler-tech/actions/commit/679f53b728468bc7e87087658394e66d7d4c8809))
* exempt internal devantler-tech deps from Dependabot cooldown ([#232](https://github.com/devantler-tech/actions/issues/232)) ([3a9a8b2](https://github.com/devantler-tech/actions/commit/3a9a8b2f7e0f761853926895ce3d1269af402bea))
* grant release-please the workflows scope for self-pin rewrites ([#337](https://github.com/devantler-tech/actions/issues/337)) ([ea68e2b](https://github.com/devantler-tech/actions/commit/ea68e2b38262a6b3a2c67a76996da63a6e8e7e82))
* guard ci.yaml test wiring and fix silently-ignored free-disk-space results ([#355](https://github.com/devantler-tech/actions/issues/355)) ([16239bb](https://github.com/devantler-tech/actions/commit/16239bb3b5174452d8d44b98ec26e9d244781dbe))
* revert tag-pin accommodations in CodeQL and zizmor configs ([#541](https://github.com/devantler-tech/actions/issues/541)) ([43773f2](https://github.com/devantler-tech/actions/commit/43773f23b3c7e84228ba2f440f24456f1217c2a8))
* scan main on push so code-scanning baseline stays current ([#275](https://github.com/devantler-tech/actions/issues/275)) ([eeb1b95](https://github.com/devantler-tech/actions/commit/eeb1b956da3ff6e18f6adb26821b3df60d531783))
* skip CI suite and dependency-review on release-please PRs ([#359](https://github.com/devantler-tech/actions/issues/359)) ([7f215f7](https://github.com/devantler-tech/actions/commit/7f215f7816adbbbc6beaba5248c5b3f9a1b91dfa))
* skip the suite on the release-commit push to dodge the self-pin tag race ([#412](https://github.com/devantler-tech/actions/issues/412)) ([91efa53](https://github.com/devantler-tech/actions/commit/91efa53fa80d71341e1546510316b18722da79f5))
* switch from Renovate to Dependabot ([#50](https://github.com/devantler-tech/actions/issues/50)) ([f1fcdf7](https://github.com/devantler-tech/actions/commit/f1fcdf7dd14ab98198c2965e222a9481098bc430))

## [9.0.12](https://github.com/devantler-tech/actions/compare/v9.0.11...v9.0.12) (2026-07-14)


### Bug Fixes

* **template-sync:** use app token for target pushes ([#585](https://github.com/devantler-tech/actions/issues/585)) ([023b103](https://github.com/devantler-tech/actions/commit/023b1035651486b96773522a7db057394dc49fd0))

## [9.0.11](https://github.com/devantler-tech/actions/compare/v9.0.10...v9.0.11) (2026-07-12)


### Bug Fixes

* **auto-merge:** harden mutable review evidence ([#575](https://github.com/devantler-tech/actions/issues/575)) ([9c8b35b](https://github.com/devantler-tech/actions/commit/9c8b35b0b25e661bc6f644b3a485e24eb1b8f25f))

## [9.0.10](https://github.com/devantler-tech/actions/compare/v9.0.9...v9.0.10) (2026-07-12)


### Bug Fixes

* **auto-merge:** fail closed on trusted-bot review gates ([#553](https://github.com/devantler-tech/actions/issues/553)) ([51ae69c](https://github.com/devantler-tech/actions/commit/51ae69cfa8f41023833719b313d3c21044f4ea60))

## [9.0.9](https://github.com/devantler-tech/actions/compare/v9.0.8...v9.0.9) (2026-07-11)


### Bug Fixes

* **auto-merge:** restrict privileged workflow to trusted bots ([#546](https://github.com/devantler-tech/actions/issues/546)) ([5a647d9](https://github.com/devantler-tech/actions/commit/5a647d98319fce3ee7abb7c9d9ed9e2870fccb52))

## [9.0.8](https://github.com/devantler-tech/actions/compare/v9.0.7...v9.0.8) (2026-07-11)


### Continuous Integration

* revert tag-pin accommodations in CodeQL and zizmor configs ([#541](https://github.com/devantler-tech/actions/issues/541)) ([43773f2](https://github.com/devantler-tech/actions/commit/43773f23b3c7e84228ba2f440f24456f1217c2a8))

## [9.0.7](https://github.com/devantler-tech/actions/compare/v9.0.6...v9.0.7) (2026-07-10)


### Bug Fixes

* **create-issues-from-todos:** preserve retry helper before checkout ([#523](https://github.com/devantler-tech/actions/issues/523)) ([be0a6cd](https://github.com/devantler-tech/actions/commit/be0a6cda17eabab73a2bf26a6519cf71bf358bb5))

## [9.0.6](https://github.com/devantler-tech/actions/compare/v9.0.5...v9.0.6) (2026-07-09)


### Bug Fixes

* **create-issues-from-todos:** avoid unpinned retry wrapper ([#518](https://github.com/devantler-tech/actions/issues/518)) ([9a54ed8](https://github.com/devantler-tech/actions/commit/9a54ed88f293d370ba22a3451965a206a176a845))

## [9.0.5](https://github.com/devantler-tech/actions/compare/v9.0.4...v9.0.5) (2026-07-09)


### Bug Fixes

* **setup-agent-skills:** recover already-installed retries ([#513](https://github.com/devantler-tech/actions/issues/513)) ([290ff61](https://github.com/devantler-tech/actions/commit/290ff61ed7c929ddb744871810142210ba4428cc))

## [9.0.4](https://github.com/devantler-tech/actions/compare/v9.0.3...v9.0.4) (2026-07-09)


### Bug Fixes

* **create-issues-from-todos:** retry-harden raw.githubusercontent.com fetches ([#484](https://github.com/devantler-tech/actions/issues/484)) ([9a04d1a](https://github.com/devantler-tech/actions/commit/9a04d1aa581c6698bf4fb81ecdf0efe37102a49a)), closes [#483](https://github.com/devantler-tech/actions/issues/483)

## [9.0.3](https://github.com/devantler-tech/actions/compare/v9.0.2...v9.0.3) (2026-07-09)


### Bug Fixes

* **ci:** cache kubeconform schemas across Test/Coverage jobs ([#476](https://github.com/devantler-tech/actions/issues/476)) ([ee2354d](https://github.com/devantler-tech/actions/commit/ee2354d9a1bad3c2fe593d1282e177be9091a3be))

## [9.0.2](https://github.com/devantler-tech/actions/compare/v9.0.1...v9.0.2) (2026-07-06)


### Bug Fixes

* **create-issues-from-todos:** stop the action self-matching its own comment ([#457](https://github.com/devantler-tech/actions/issues/457)) ([5188832](https://github.com/devantler-tech/actions/commit/518883207726c973c00f15b138109daa1e27fba5))

## [9.0.1](https://github.com/devantler-tech/actions/compare/v9.0.0...v9.0.1) (2026-07-06)


### Bug Fixes

* **create-issues-from-todos:** re-pin todo-to-issue-action to v5.1.15 ([#451](https://github.com/devantler-tech/actions/issues/451)) ([6415df0](https://github.com/devantler-tech/actions/commit/6415df0803ed03600ceb77f3725b678254469459)), closes [#222](https://github.com/devantler-tech/actions/issues/222)

## [9.0.0](https://github.com/devantler-tech/actions/compare/v8.0.2...v9.0.0) (2026-07-03)


### ⚠ BREAKING CHANGES

* remove the sync-github-labels composite action (superseded by declarative IssueLabels) ([#418](https://github.com/devantler-tech/actions/issues/418))
* All callers referencing old file names, input names, output names, or secret keys must be updated.
* **run-dotnet-tests:** run-dotnet-tests no longer accepts app-id or app-private-key inputs. Callers pinning by SHA are unaffected; on repin any still-passed values are simply ignored (unexpected-input warning).
* the `setup-copilot-skills`/`update-copilot-skills` action paths are removed and `setup-agent-skills`'s `agent` input is renamed to `agents`. Consumers on a pinned major (e.g. @v4) are unaffected until they bump; migration guides are in each action's README.
* the `codecov-token` input is removed from both actions. Callers must stop passing it (the reusable workflows are updated in lockstep).
* **copilot-skills:** `setup-copilot-skills` and `update-copilot-skills` both remove the `skills-lock` input; `setup-copilot-skills` also removes the `source` input and redefines `skills` as the sole list input. Delete any skills-lock.json and move each entry onto its own `<owner/repo> <skill>` line in `setup-copilot-skills.with.skills`.
* Action directories and input names have been renamed.

### Features

* add .NET project and test configurations ([#10](https://github.com/devantler-tech/actions/issues/10)) ([1ce56da](https://github.com/devantler-tech/actions/commit/1ce56da8d25676b7a9674b7c896f75e06da2caf1))
* add `require-checks-in-pr` composite action ([#113](https://github.com/devantler-tech/actions/issues/113)) ([1f66c91](https://github.com/devantler-tech/actions/commit/1f66c91d45d374ceac9fe830a783444ebc9be958))
* add auto-merge composite action for PRs ([#14](https://github.com/devantler-tech/actions/issues/14)) ([a8f34bd](https://github.com/devantler-tech/actions/commit/a8f34bd9d1876705e326007885beaa5f8c5901d0))
* add automation configuration for PR reviews and issue sessions ([f4b7152](https://github.com/devantler-tech/actions/commit/f4b7152947fd620413b3376039707ae46eaba6f0))
* add blocked label and update label sync configuration ([3041247](https://github.com/devantler-tech/actions/commit/3041247268b5f379c31e2d76e72fb4df2785791e))
* add Calculator class with basic arithmetic operations and corresponding unit tests ([f5c21a1](https://github.com/devantler-tech/actions/commit/f5c21a10dc535c6b57f0b4250b31c746b33f609b))
* add collapsible sections for workflow details in README ([2e8d0f9](https://github.com/devantler-tech/actions/commit/2e8d0f97c5d593034954b3aef61ca946f7adf506))
* add docs ([aba6c52](https://github.com/devantler-tech/actions/commit/aba6c52629877c30388ccdd51a42090a9e60ec6c))
* add dotnet-test-action for testing .NET solutions with GitHub Actions ([ad39d59](https://github.com/devantler-tech/actions/commit/ad39d59cd6526ed6863f4b3f5a6564235087d728))
* add EditorConfig file and update Calculator and CalculatorTests for consistency and clarity ([f032439](https://github.com/devantler-tech/actions/commit/f0324397fd2905cbe7b6a60833fe15eb2b803949))
* add GitHub workflows ([861d3e2](https://github.com/devantler-tech/actions/commit/861d3e2233ae32b5f4203e54e70971a2f018138b))
* add GitOps deployment workflow for managing Kubernetes resources ([f6f0ce7](https://github.com/devantler-tech/actions/commit/f6f0ce73c7c2938b829c6c76b4452421c8ad0c7d))
* add GitOps validation workflow ([8505da2](https://github.com/devantler-tech/actions/commit/8505da27affc0478bd012161782bfd2d27887c2e))
* add Hadolint action for linting Dockerfiles ([9f610a8](https://github.com/devantler-tech/actions/commit/9f610a89adae6fd6822da5461cc5e4044963d366))
* add Homebrew setup and environment initialization to GitOps workflows ([c4b0fe5](https://github.com/devantler-tech/actions/commit/c4b0fe5e636ab5b7f71067e3bc739fa7eb7dd9aa))
* add Homebrew setup step to GitOps workflows for consistent environment setup ([e300bd6](https://github.com/devantler-tech/actions/commit/e300bd64d259dce258cd8a8b1285e0cbcbbe04b0))
* add initial release configuration for semantic-release ([3c4f906](https://github.com/devantler-tech/actions/commit/3c4f906628c9abb2224ffbc661cc38a3e639f31f))
* add inputs for HOSTS_FILE and ROOT_CA_CERT_FILE in GitOps workflow ([6eefeeb](https://github.com/devantler-tech/actions/commit/6eefeeb6a085cf87afa7915911f7f9d4049797b5))
* add pull_request and merge_group triggers to Zizmor workflow ([1ce3f4b](https://github.com/devantler-tech/actions/commit/1ce3f4b21cdb1b5dfef7b8f629fe3335677d9618))
* add pull_request trigger to auto-merge and dotnet-test workflows ([63097da](https://github.com/devantler-tech/actions/commit/63097da91cc7f4dd04672119ec2094dfe0deeb4b))
* add pull_request trigger to GitOps lint and test workflows ([dbd5fe8](https://github.com/devantler-tech/actions/commit/dbd5fe80d87f05a00230b2b423f6b562b6726d6b))
* add released label to labels configuration ([a803193](https://github.com/devantler-tech/actions/commit/a803193ff0bec05a9d49ac6ae68df55c232cf20e))
* add Repo Assist labels to central config ([#161](https://github.com/devantler-tech/actions/issues/161)) ([b41fbfe](https://github.com/devantler-tech/actions/commit/b41fbfe687a0737a25ebe9ea749b95ad09c5c92e))
* add reusable workflow to sync upstream Kyverno policies and update README with usage instructions ([b119b9f](https://github.com/devantler-tech/actions/commit/b119b9fc03d4ca7cdff1b8ac64ee50034a267a88))
* add schedule trigger for sync labels workflow ([5f3527e](https://github.com/devantler-tech/actions/commit/5f3527e1928c288eaec633fcba8328489f5bdbe2))
* add shared workflows ([0fe78df](https://github.com/devantler-tech/actions/commit/0fe78df1a7408538ec22772ea019d777a9c82451))
* add step to append hosts file if it exists ([6f22cd1](https://github.com/devantler-tech/actions/commit/6f22cd124ad77fcf05101d631e57ba0d1ef3ae10))
* add upload-coverage action for GitHub Code Quality ([#170](https://github.com/devantler-tech/actions/issues/170)) ([60d895a](https://github.com/devantler-tech/actions/commit/60d895a7aabe6e3c0247c86a83560656a760ee08))
* add upsert-issue composite action ([#55](https://github.com/devantler-tech/actions/issues/55)) ([e3a0bd5](https://github.com/devantler-tech/actions/commit/e3a0bd51f2159079c77872080d493bc5ab9dc8bc))
* add VERSION_ARGS input to dotnet-embed-binaries workflow for version retrieval ([a648561](https://github.com/devantler-tech/actions/commit/a6485616ea76eb97174bc9ff388ee1f1b33cf69a))
* add workflow for cleaning up ghcr packages ([856fea4](https://github.com/devantler-tech/actions/commit/856fea4dbe245af4bfdc2016da174512e01ff9ca))
* add Zizmor composite action workflow ([c0b70d3](https://github.com/devantler-tech/actions/commit/c0b70d316dbb9ecba4b62a63a2fa77f2254b59b8))
* add Zizmor security analysis workflow and action documentation ([dbae7c7](https://github.com/devantler-tech/actions/commit/dbae7c74313bbec6b915fa9daadb3d425a3741de))
* add Zizmor workflow configuration ([6e1f9b5](https://github.com/devantler-tech/actions/commit/6e1f9b592bc7d79e2da668a40c2004e3d661376f))
* add Zizmor workflow configuration ([2b9e59f](https://github.com/devantler-tech/actions/commit/2b9e59fc9600d242bb6699debef21e87fdbee78e))
* add Zizmor workflow configuration ([5f1126b](https://github.com/devantler-tech/actions/commit/5f1126bd93fc1b942c676142fa16622fd88a1340))
* **cleanup-ghcr-packages:** add dry-run/package inputs and CI smoke test ([#193](https://github.com/devantler-tech/actions/issues/193)) ([1dddb9d](https://github.com/devantler-tech/actions/commit/1dddb9d8e7f448a5880d05695742b35960da5bb0))
* **copilot-skills:** drop lockfile, lean on gh skill frontmatter ([#95](https://github.com/devantler-tech/actions/issues/95)) ([7906319](https://github.com/devantler-tech/actions/commit/79063198d351a69bbd89369465004417ab01f173))
* **create-issues-from-todos:** support client-id, deprecate app-id ([#271](https://github.com/devantler-tech/actions/issues/271)) ([9d98cb8](https://github.com/devantler-tech/actions/commit/9d98cb8be059537ec1e82f71c90d75ecba321713))
* **dependency-review:** add composite for GitHub Dependency Review ([#217](https://github.com/devantler-tech/actions/issues/217)) ([21b2937](https://github.com/devantler-tech/actions/commit/21b29372cc10d4dedd8e78964c1f29742b970124))
* **diagnose-flux:** add shared composite action for Flux failure diagnostics ([#368](https://github.com/devantler-tech/actions/issues/368)) ([d59a53c](https://github.com/devantler-tech/actions/commit/d59a53caea9f54b2782c44ea3fc3ee2088b20012))
* **free-disk-space:** add composite action to reclaim runner disk ([#214](https://github.com/devantler-tech/actions/issues/214)) ([cbfd433](https://github.com/devantler-tech/actions/commit/cbfd433920d036c336b00b35af4c82f8e700affe))
* implement dotnet-test action with coverage reporting ([b4b4aac](https://github.com/devantler-tech/actions/commit/b4b4aac006abe7897239ab2e3877622fd27ca96b))
* merge reusable-workflows into the actions repo ([#314](https://github.com/devantler-tech/actions/issues/314)) ([b282265](https://github.com/devantler-tech/actions/commit/b282265e912820d25dd90248d1b1a910a0b4ce94))
* normalize secret input keys to UPPER_SNAKE_CASE ([#69](https://github.com/devantler-tech/actions/issues/69)) ([82ef4a7](https://github.com/devantler-tech/actions/commit/82ef4a7640f552468d56d1a142c4ad796faa2f6d))
* remove Codecov upload from coverage actions ([#175](https://github.com/devantler-tech/actions/issues/175)) ([7dbc3c3](https://github.com/devantler-tech/actions/commit/7dbc3c310c46eb51b0f298de2de0e2d9c6552eae))
* remove the sync-github-labels composite action (superseded by declarative IssueLabels) ([#418](https://github.com/devantler-tech/actions/issues/418)) ([0d7ff03](https://github.com/devantler-tech/actions/commit/0d7ff030438799e3bb423a8649115ad2b36ee78f))
* rename copilot-skills actions to agent-neutral agent-skills ([#178](https://github.com/devantler-tech/actions/issues/178)) ([3556694](https://github.com/devantler-tech/actions/commit/3556694b57702d81bfc5fb1d79a9ee0b4e53aca7))
* rename require-checks-in-pr to aggregate-job-checks ([#154](https://github.com/devantler-tech/actions/issues/154)) ([59d3ffb](https://github.com/devantler-tech/actions/commit/59d3ffbe1a9437fcc39e2794fa2f221abe878310))
* **run-dotnet-tests:** provision .NET 10 SDK alongside 9 ([#186](https://github.com/devantler-tech/actions/issues/186)) ([6916c45](https://github.com/devantler-tech/actions/commit/6916c45ed8dc22e62cb12f021480e29732d03575))
* **setup-copilot-skills:** add composite action to install gh skills ([#74](https://github.com/devantler-tech/actions/issues/74)) ([b35a193](https://github.com/devantler-tech/actions/commit/b35a1930f8bbba09bd6ea30fc9b49e9fbdb969a7))
* standardize actions with verb-purpose naming, add new actions and CI improvements ([#52](https://github.com/devantler-tech/actions/issues/52)) ([8d9a6d9](https://github.com/devantler-tech/actions/commit/8d9a6d91f094d4ce628381949f08c84632e7ac27))
* Update README and add new composite actions ([c401eac](https://github.com/devantler-tech/actions/commit/c401eaca053e4a385c4b59269c6e859df2599890))
* **update-copilot-skills:** auto-discover skill root directories ([#103](https://github.com/devantler-tech/actions/issues/103)) ([4489b81](https://github.com/devantler-tech/actions/commit/4489b810277f6c3ebbbe4626eee66e92e1a556e4))
* **update-copilot-skills:** pin resolved skill refs back into skills-lock.json ([#88](https://github.com/devantler-tech/actions/issues/88)) ([7c34831](https://github.com/devantler-tech/actions/commit/7c348311ff027f53036cbed500d5638511989310))
* upload .NET coverage to GitHub Code Quality ([#174](https://github.com/devantler-tech/actions/issues/174)) ([31d3c27](https://github.com/devantler-tech/actions/commit/31d3c2706ca08bb65fc26002d63a8483965b6570))


### Bug Fixes

* add checks to skip creation of OCI source and Kustomization if they already exist ([1fa3f17](https://github.com/devantler-tech/actions/commit/1fa3f17cf87dbea102184693c2c4726883bf17bd))
* add conditional check for Cilium installation in GitOps workflow ([e2857f0](https://github.com/devantler-tech/actions/commit/e2857f0cb5c669227b7e21d17e19f5106a669d40))
* add Copilot user to auto-merge condition ([cc639cb](https://github.com/devantler-tech/actions/commit/cc639cbd1f84fc614507f8441c824a944af37541))
* add dependency input for GitHub repo in dotnet-test workflow ([7ec8e76](https://github.com/devantler-tech/actions/commit/7ec8e76fa11c2422656b2f929861a388e7be45ad))
* add dependency on bootstrap job in deploy workflow ([eb8aee2](https://github.com/devantler-tech/actions/commit/eb8aee2be468b234f2c26d89399c737fb737855f))
* add deploy-dev job to handle deployment in GitOps workflow ([16d57d9](https://github.com/devantler-tech/actions/commit/16d57d9cf7f682a16b4d12fc7a5c3b9e6ab64556))
* add environment context to all jobs in gitops-deploy workflow ([29e3d6a](https://github.com/devantler-tech/actions/commit/29e3d6a330e7573963687f184755e318c1d46a3b))
* add GitHub Packages as NuGet source in dotnet-test workflow ([3c30545](https://github.com/devantler-tech/actions/commit/3c305458b32fb015f27deba1644412f4b9d01946))
* add merge_group event to auto-merge workflow ([0a18f95](https://github.com/devantler-tech/actions/commit/0a18f9501a7316084a4e544031cec75d70779778))
* add merge_group to GitOps test workflow ([c7063db](https://github.com/devantler-tech/actions/commit/c7063db2fe03e4248687c6e4a756b6ed598bd940))
* add merge_group to workflow triggers in dotnet-test and image-lint workflows ([57c8045](https://github.com/devantler-tech/actions/commit/57c80456b8ac78c8605d1a93da0d7a02ae595909))
* add merge_group trigger to GitOps validate workflow ([97a9e8c](https://github.com/devantler-tech/actions/commit/97a9e8c2c310491b356aed573dbf90ded409de05))
* add missing 'renovate[bot]' user login reference in auto-merge action workflow ([e2bd116](https://github.com/devantler-tech/actions/commit/e2bd11618534558a19a1903468a9f1ba5daf90db))
* add missing checkout step in reusable workflow for cluster bootstrap ([062dacb](https://github.com/devantler-tech/actions/commit/062dacbd315d0720a0eecc26398d67a9b4efc5cf))
* add missing connection in workflow diagram in README ([ea35790](https://github.com/devantler-tech/actions/commit/ea35790954508503d468b19f6a17e84631325d47))
* add missing continuation for cgroup.hostRoot setting in Cilium installation ([e362800](https://github.com/devantler-tech/actions/commit/e3628007bc048db3c46c2d6c3b979ca447b85efb))
* add missing wait flag for Cilium installation in GitOps workflow ([dadc93f](https://github.com/devantler-tech/actions/commit/dadc93f67f244af913232448ee44f14f29b74b6a))
* add mtls to cilium in bootstrap step ([e914ff3](https://github.com/devantler-tech/actions/commit/e914ff38416997457b8fae954cc8717863b67a1d))
* add permissions section for GitOps workflow ([675818e](https://github.com/devantler-tech/actions/commit/675818efda4dcfd9dec9e7250a6797b779935d0a))
* add push trigger for main branch in release workflow ([3fa15c1](https://github.com/devantler-tech/actions/commit/3fa15c1ec6af7d89d1e69e1bfb546936105cadef))
* add reusable TODOs workflow ([5d0d10c](https://github.com/devantler-tech/actions/commit/5d0d10ce1e8dca5b58accc8cfa07f14f15319c41))
* add suspend and resume commands for kustomization in reconcile step ([3d82e8d](https://github.com/devantler-tech/actions/commit/3d82e8dc55e52d1f8a1c1a6e24b5794721a3f859))
* add workflow_dispatch trigger to sync labels workflow ([531e764](https://github.com/devantler-tech/actions/commit/531e764ad02d5c4495b49141293e6589e9533b1c))
* address review feedback on `require-checks-in-pr` action ([#116](https://github.com/devantler-tech/actions/issues/116)) ([8fa6997](https://github.com/devantler-tech/actions/commit/8fa6997294452d1cf0982ff0925712a326c46c0c))
* allow 'devantler' to trigger auto-merge job ([7b8d8c9](https://github.com/devantler-tech/actions/commit/7b8d8c98f6c6d37221adc35e08f102ee68694810))
* allow NuGet push to continue on error ([5baba33](https://github.com/devantler-tech/actions/commit/5baba3319dd1e2d748dd7828ffa67c943db66b16))
* **approve-pr,upsert-issue:** retry-harden unguarded gh network calls ([#405](https://github.com/devantler-tech/actions/issues/405)) ([7fe5fad](https://github.com/devantler-tech/actions/commit/7fe5fad50cfbf15b3c62f05aa73964d3022fb155))
* correct condition syntax for dependency installation in dotnet-test workflow ([382545e](https://github.com/devantler-tech/actions/commit/382545ed462bfddd1bf31ecbc7ec1188b304cad0))
* correct emphasis on "Composite Action" in diagram ([865a142](https://github.com/devantler-tech/actions/commit/865a14280b732be27e42175b57e7159823c54dd6))
* correct formatting of auto-merge condition for consistency ([b0b8a4e](https://github.com/devantler-tech/actions/commit/b0b8a4ee422a6e87667221008a740d2a7c6e9c19))
* correct indentation in flux tag artifact command ([8710100](https://github.com/devantler-tech/actions/commit/87101008c8bff70b3d99f8a81bf7547b68a60305))
* correct syntax for dependency condition in dotnet-test workflow ([dd3795d](https://github.com/devantler-tech/actions/commit/dd3795d396a339d50cd32dcac883f99265fa486a))
* correct terminology in workflow diagram in README ([ce725cb](https://github.com/devantler-tech/actions/commit/ce725cb74f3c626668621b6ebeaba5a16c33236d))
* correct user login reference in auto-merge action workflow ([f11f256](https://github.com/devantler-tech/actions/commit/f11f256c8949820880c88451dca0a256c2d636e1))
* correct wording in README introduction for clarity ([17ebd8b](https://github.com/devantler-tech/actions/commit/17ebd8ba893a97c3f7e9d983d6401dcad961c8d2))
* Delete .github/workflows/active-enable-auto-merge.yaml ([a533979](https://github.com/devantler-tech/actions/commit/a5339799d371b6952e7d3abdc9ea1ca096a28dfe))
* **deps:** update create-github-app-token action to v2.2.1 ([884a9b7](https://github.com/devantler-tech/actions/commit/884a9b7321e269351d5fc006d95e0b50b2ddedf6))
* disable kubeProxyReplacement in Cilium installation ([74e7ef8](https://github.com/devantler-tech/actions/commit/74e7ef8d4e4503295cfb55d2a6fcbf77f6709f07))
* enable Gateway API features in Cilium installation ([938ee58](https://github.com/devantler-tech/actions/commit/938ee5865b95bcc64631b4511d8ce618f2cf6df2))
* enable kubeProxyReplacement and set k8sServiceHost and k8sServicePort in Cilium installation ([cfb0fa0](https://github.com/devantler-tech/actions/commit/cfb0fa09089a80263d20af4ed37d3c04254d6433))
* **enable-auto-merge-on-pr:** retry-harden the gh API/merge network calls ([#402](https://github.com/devantler-tech/actions/issues/402)) ([b0e24b5](https://github.com/devantler-tech/actions/commit/b0e24b53dfef88cbd1a2a22c7451454191bc4559)), closes [#401](https://github.com/devantler-tech/actions/issues/401)
* enhance ksail update command with deployment tool specification ([d9515f6](https://github.com/devantler-tech/actions/commit/d9515f63d5640e448f278ab2a11e369acd705bd8))
* ensure token is passed during checkout step in auto-merge workflow ([8ac9c47](https://github.com/devantler-tech/actions/commit/8ac9c478218c1df17308c56b7bc18f37463843c7))
* **github-app:** update automation settings for PR review and remote control ([17691ce](https://github.com/devantler-tech/actions/commit/17691ce06f7c2324d7a41a60ec9cc3baf471bfea))
* **labels:** add roadmap to canonical label set so weekly sync stops deleting it ([#253](https://github.com/devantler-tech/actions/issues/253)) ([b31ec7b](https://github.com/devantler-tech/actions/commit/b31ec7baa4d7e9ca5b113f56cc928fe708872431))
* move Renovate configuration file ([a6290f7](https://github.com/devantler-tech/actions/commit/a6290f7afc77e94d2e2b5b4f2fd7046210ea7352))
* normalize action input names ([#72](https://github.com/devantler-tech/actions/issues/72)) ([961f62f](https://github.com/devantler-tech/actions/commit/961f62f4a771b31e48acaae4a619cef6c7fe2195))
* pass skills directory to gh skill update to fix write path ([#108](https://github.com/devantler-tech/actions/issues/108)) ([907b940](https://github.com/devantler-tech/actions/commit/907b9400e06b1ad77813d1200ba7945a2e329e00))
* refine condition for auto-merge job to include pull request event ([e018b2e](https://github.com/devantler-tech/actions/commit/e018b2e97916132f18d3eee1277e61ba52ae9900))
* remove deploy-dev job from GitOps test workflow ([bd7d1f2](https://github.com/devantler-tech/actions/commit/bd7d1f212bc5d70147112bc2bc410bf52134da9d))
* remove draft check from .NET test job ([b4316e1](https://github.com/devantler-tech/actions/commit/b4316e1a2dd3f04c6e6f8d1c1049082675e25895))
* remove forwardKubeDNSToHost setting from Cilium installation ([fc832f4](https://github.com/devantler-tech/actions/commit/fc832f490f4119b44aca760a0556f77e88fc7ee7))
* remove hardcoded project reference in todos.yaml ([c9cac8d](https://github.com/devantler-tech/actions/commit/c9cac8dbf9fb6439059b64a96fbb8b7d31439e4b))
* remove outdated README for zizmor-action ([9f610a8](https://github.com/devantler-tech/actions/commit/9f610a89adae6fd6822da5461cc5e4044963d366))
* remove PROJECTS_SECRET from todos.yaml ([8bfb9f8](https://github.com/devantler-tech/actions/commit/8bfb9f8c1d3439b144b7418cf59a9f7269fd9da0))
* remove unnecessary dependency on bootstrap job in push-to-oci ([dcf76df](https://github.com/devantler-tech/actions/commit/dcf76dfd2786ce60b778050985cf947f1198cf72))
* remove unused merge_group trigger from auto-merge workflow ([7698978](https://github.com/devantler-tech/actions/commit/76989782262d34128df91046f112d7e04f78c360))
* remove Zizmor Action and its documentation ([005c37f](https://github.com/devantler-tech/actions/commit/005c37f8ef5e1811388cf19b3b93eb721351b6be))
* rename job from auto-approve to auto-merge in workflow ([c24fbfb](https://github.com/devantler-tech/actions/commit/c24fbfb0186e2e122cc2976a914de7e956f68473))
* rename job from lint to validate in GitOps workflow ([5603f0e](https://github.com/devantler-tech/actions/commit/5603f0ec91ba2845c439f95d5fe200210127bc33))
* rename jobs in GitHub workflows for consistency ([625fd3b](https://github.com/devantler-tech/actions/commit/625fd3b150679c433ebd0dd351151f0aae6973ad))
* rename secret key to match reusable workflow definition ([#60](https://github.com/devantler-tech/actions/issues/60)) ([095e4c8](https://github.com/devantler-tech/actions/commit/095e4c8b58902168206ca3899b2ab9fbce9b1bcf))
* reorder checkout action in todos workflow ([391f482](https://github.com/devantler-tech/actions/commit/391f482cb718cdb35c8fb41cc6047571d4fbc7ca))
* replace Flux installation with KSail installation in deploy step ([41ab5a7](https://github.com/devantler-tech/actions/commit/41ab5a7b82564aec5a63190c1fc2b978a1ec016f))
* replace manual Homebrew installation with action for consistency across workflows ([0bb1e09](https://github.com/devantler-tech/actions/commit/0bb1e09f81280ee12233c50c6ff20282fbd10413))
* replace manual KSail installation with Homebrew for consistency across workflows ([505a5ce](https://github.com/devantler-tech/actions/commit/505a5cec16d888b02fbc3dd8478c16b831407e26))
* **require-checks-in-pr:** restore graceful handling of empty job-results ([#138](https://github.com/devantler-tech/actions/issues/138)) ([19f1f2e](https://github.com/devantler-tech/actions/commit/19f1f2e8c01aeafe037af8ca26d8c2dab1dee2a4))
* resolve first-party self-references at the same commit ([#427](https://github.com/devantler-tech/actions/issues/427)) ([96b8f82](https://github.com/devantler-tech/actions/commit/96b8f82c71f7837eed166f65b173019b164676c6))
* restore permissions for issues in todos.yaml ([b1f4c87](https://github.com/devantler-tech/actions/commit/b1f4c876a02ab7b2bded19d3b050ed67db98a818))
* **run-dotnet-tests:** gate coverage upload on runner.os, not the unavailable matrix context ([#241](https://github.com/devantler-tech/actions/issues/241)) ([8ce1952](https://github.com/devantler-tech/actions/commit/8ce19528eda1ef50f3d028b685c53aebaed6ae62))
* sanitize tag name for OCI artifact in deployment workflow ([61201e1](https://github.com/devantler-tech/actions/commit/61201e1099d9bac0f0ea60c0d200542618c5e26d))
* **scan-for-todo-comments:** restore self-checkout for post-cleanup ([#437](https://github.com/devantler-tech/actions/issues/437)) ([6f07366](https://github.com/devantler-tech/actions/commit/6f07366d6367e420f129bf73b1d9bdc8b54525b3))
* scope GitHub App tokens to least privilege (zizmor github-app) ([#279](https://github.com/devantler-tech/actions/issues/279)) ([40816ac](https://github.com/devantler-tech/actions/commit/40816acee2940a3b46bd5c042a023ee24528353b)), closes [#274](https://github.com/devantler-tech/actions/issues/274)
* set forwardKubeDNSToHost to false in Cilium installation ([48d3003](https://github.com/devantler-tech/actions/commit/48d30037de9edec6537339992fe8181c2a7c9ba3))
* **setup-copilot-skills:** default scope to repo for CI use ([#85](https://github.com/devantler-tech/actions/issues/85)) ([5383a2b](https://github.com/devantler-tech/actions/commit/5383a2b945b5776b0fc9299d182a2db382af352f))
* **setup-copilot-skills:** install gh on demand when runner has an older version ([#76](https://github.com/devantler-tech/actions/issues/76)) ([538d710](https://github.com/devantler-tech/actions/commit/538d7103ed24531647941b3a460393b5ac7ed756))
* **setup-ksail-cli:** trust first-party tap so brew can load the KSail Cask ([#262](https://github.com/devantler-tech/actions/issues/262)) ([7848ec0](https://github.com/devantler-tech/actions/commit/7848ec0b7adcfeaf4d50d8483c4da28adf378171))
* simplify auto-merge condition formatting for readability ([3f4f428](https://github.com/devantler-tech/actions/commit/3f4f428c7388c21bb27c56cda6502589a4654d68))
* simplify auto-merge condition formatting in workflow ([6b44303](https://github.com/devantler-tech/actions/commit/6b443031e1ae99ec27f7cc48a050591b2ab813af))
* simplify dependency installation condition in dotnet-test workflow ([e4171c4](https://github.com/devantler-tech/actions/commit/e4171c4c7bd37c8eec3861f90a61ba41f13334b9))
* specify version for reusable workflow in active-release.yaml ([b2d85ee](https://github.com/devantler-tech/actions/commit/b2d85eefa2d5a75ee53571910e29080c5bdd271a))
* update action paths in workflow files to use local references ([44620f6](https://github.com/devantler-tech/actions/commit/44620f6c6e9bc2046c7959932fbd104a74d6b1a5))
* update action references to specific versions in multiple workflows ([d69de4b](https://github.com/devantler-tech/actions/commit/d69de4b313f789d5aff0bf42614da212fc5362e2))
* Update action.yaml ([f378f06](https://github.com/devantler-tech/actions/commit/f378f06c871bf640a57ec20466a4f54d38d35587))
* update actions/checkout to persist-credentials: false for improved security ([df6427f](https://github.com/devantler-tech/actions/commit/df6427f6e447c66e51243889e989e4a557fa13bb))
* update auto-merge condition formatting for clarity ([85a3844](https://github.com/devantler-tech/actions/commit/85a3844aa6c46d8459d37d0d90c22f6107195ff4))
* update auto-merge condition to exclude draft pull requests ([7ba542f](https://github.com/devantler-tech/actions/commit/7ba542fee6165e00949e49e2cab2ef42b98d5d4a))
* update auto-merge condition to exclude draft pull requests ([f6c779a](https://github.com/devantler-tech/actions/commit/f6c779a9be5a6ba8a831d98909d734f7af9127cc))
* update auto-merge workflow to use GitHub App Token for authentication ([f2b7abc](https://github.com/devantler-tech/actions/commit/f2b7abcc15f2e66bce8fb466059a9bc201365ca7))
* update auto-merge-action reference to specific commit for consistency ([b8298f5](https://github.com/devantler-tech/actions/commit/b8298f5d8bb6d8b1d807c22ec9847889b1471858))
* update condition for auto-merge job to use pull request user login ([b58c3a0](https://github.com/devantler-tech/actions/commit/b58c3a07e91dd91a5a39bc2108e88337805ca458))
* update dependency installation condition to use env variable ([8b28c8c](https://github.com/devantler-tech/actions/commit/8b28c8c3b4dc4f3512ef1ebb6637fef264cc1bc7))
* update diagram in README to accurately represent workflow relationships ([ff00c64](https://github.com/devantler-tech/actions/commit/ff00c64742b4f47d07a3ac8f2c4c47833e73e6f0))
* update dotnet-test action reference to use the latest version ([e146fe7](https://github.com/devantler-tech/actions/commit/e146fe7ecda9d78314d6378b0401d2ceaff370e1))
* update dotnet-test-action usage to local path ([74fdadf](https://github.com/devantler-tech/actions/commit/74fdadf32eb1b2a199e557f9ca92c4e0206a0c7b))
* update dotnet-test-action usage to local path and add working directory ([#13](https://github.com/devantler-tech/actions/issues/13)) ([3685954](https://github.com/devantler-tech/actions/commit/3685954ea951eff2f2b5e858ce8534e662b27237))
* update EndBug/label-sync action to specific commit for stability ([4c00454](https://github.com/devantler-tech/actions/commit/4c004547d1487bb0fd9e3801917c015eed52378a))
* update GitHub Actions relationship diagram for clarity and accuracy ([0df4ee9](https://github.com/devantler-tech/actions/commit/0df4ee9f2a1169c870bb5f8eea023674cdf4d2ea))
* update host and root CA file checks to use vars fallback ([b891ccc](https://github.com/devantler-tech/actions/commit/b891ccc71d7c324945e44b0476ad04173a90954d))
* update name of NuGet source step to reflect GHCR usage ([baaf98b](https://github.com/devantler-tech/actions/commit/baaf98b068289086e9b0fa3eab8aa2093fdbf7c1))
* update output setting for current Kubernetes context in reconcile step ([08a2df7](https://github.com/devantler-tech/actions/commit/08a2df782236b6eb0fa547e6d62c91af6c6f850e))
* update README to include links for reusable workflows and composite actions ([715aedf](https://github.com/devantler-tech/actions/commit/715aedfa4862b2673db46f6c0c72ab5783391f90))
* update reusable workflow callsites for naming refactor ([#53](https://github.com/devantler-tech/actions/issues/53)) ([73f2eb4](https://github.com/devantler-tech/actions/commit/73f2eb403e2337c84e704adb2fcea86b71ac438a))
* update workflow diagram to correct relationships and add missing connections ([88bed98](https://github.com/devantler-tech/actions/commit/88bed98480665836a301b340bdc35db1afa8e391))
* update workflow reference in active-release.yaml ([d4b23f9](https://github.com/devantler-tech/actions/commit/d4b23f9e20423712a3300a63bdbaf4ac70fee721))
* update zizmor action reference to specific commit for consistency ([3899a97](https://github.com/devantler-tech/actions/commit/3899a97c25519bda7685b665a7afd0064468f22f))
* update Zizmor workflow triggers to use workflow_call only ([9b0d3e7](https://github.com/devantler-tech/actions/commit/9b0d3e77f78a8de4d03006e9b860afebbab75207))
* **update-copilot-skills:** address post-merge review comments ([#92](https://github.com/devantler-tech/actions/issues/92)) ([bf04cc0](https://github.com/devantler-tech/actions/commit/bf04cc00fffcc37b573cdf045556f3f26fe9fe8c))
* **upsert-issue:** fail with a clear error when body-file is missing ([#385](https://github.com/devantler-tech/actions/issues/385)) ([aabeddb](https://github.com/devantler-tech/actions/commit/aabeddb5c8d5061b9454bdc32aec7a3724bca498))
* use UPPER_SNAKE_CASE for secret input keys ([#67](https://github.com/devantler-tech/actions/issues/67)) ([f99f6c9](https://github.com/devantler-tech/actions/commit/f99f6c990a696a8c8d48141ff04ea4244a763c20))
* **workflows:** revert step-security actions to original authors ([#134](https://github.com/devantler-tech/actions/issues/134)) ([5daa8b5](https://github.com/devantler-tech/actions/commit/5daa8b5b0b53c70ee24446ec76089515ec6cd6db))


### Code Refactoring

* **agent-skills:** share the gh bootstrap via one script ([#211](https://github.com/devantler-tech/actions/issues/211)) ([14c9fed](https://github.com/devantler-tech/actions/commit/14c9fed2dc9b005a16e2676114f51be0aad50b9e))
* **approve-pr:** accept client-id, deprecate app-id input ([#290](https://github.com/devantler-tech/actions/issues/290)) ([555e27d](https://github.com/devantler-tech/actions/commit/555e27de34b0f0f6b5aacb6fd82f24251225acac))
* consolidate test workflows into single ci.yaml ([#121](https://github.com/devantler-tech/actions/issues/121)) ([3b7af5b](https://github.com/devantler-tech/actions/commit/3b7af5b8d83a7c2ceb664ae7314444b9c6811c9f))
* remove workflow_dispatch and merge_group triggers from multiple workflows ([ba4dab8](https://github.com/devantler-tech/actions/commit/ba4dab84be72ffe0fabda52006a5a58dd3e68fc2))
* rename job in dotnet-embed-binaries workflow ([10ef47a](https://github.com/devantler-tech/actions/commit/10ef47a82d2473e5402fe0633ab8db1b9384a6b8))
* rename secret inputs to kebab-case ([#65](https://github.com/devantler-tech/actions/issues/65)) ([33461ab](https://github.com/devantler-tech/actions/commit/33461abe2a10a5375807204f3629d3e8fe9fa288))
* rename workflow for embedding binaries in .NET projects ([c084677](https://github.com/devantler-tech/actions/commit/c084677aad3aeb65425a2146dd9df1c5ba01fb14))
* replace inline status-check jobs with require-checks-in-pr action ([#118](https://github.com/devantler-tech/actions/issues/118)) ([e5a89fd](https://github.com/devantler-tech/actions/commit/e5a89fd767ca94e815d1dab2cd42cb7ee4e3d2e9))
* **run-dotnet-tests:** drop dead app-id/app-private-key inputs ([#264](https://github.com/devantler-tech/actions/issues/264)) ([0e12329](https://github.com/devantler-tech/actions/commit/0e1232924bf8b07a40b1b24e13e200744fbabcfa))
* split enable-auto-merge-on-pr into approve-pr and enable-auto-merge-on-pr ([#58](https://github.com/devantler-tech/actions/issues/58)) ([ba49255](https://github.com/devantler-tech/actions/commit/ba492559ea1bd82fdb0755e3e936dfa6db83be8f))


### Continuous Integration

* add enable-auto-merge workflow ([#110](https://github.com/devantler-tech/actions/issues/110)) ([ae7c660](https://github.com/devantler-tech/actions/commit/ae7c6604c9dcef5a17b20be9b52d533894597178))
* add README↔action.yaml input/output parity guard ([#197](https://github.com/devantler-tech/actions/issues/197)) ([6d8bcd6](https://github.com/devantler-tech/actions/commit/6d8bcd616576371b9ae9a17421dfed8a7ee5501b))
* add shared retry.sh and bound setup-ksail-cli network pulls ([#302](https://github.com/devantler-tech/actions/issues/302)) ([b2c1104](https://github.com/devantler-tech/actions/commit/b2c1104d8a0ce00a089e340d2f5937bcff54e348))
* bound gh-skill network pulls with shared retry helper ([#308](https://github.com/devantler-tech/actions/issues/308)) ([679f53b](https://github.com/devantler-tech/actions/commit/679f53b728468bc7e87087658394e66d7d4c8809))
* exempt internal devantler-tech deps from Dependabot cooldown ([#232](https://github.com/devantler-tech/actions/issues/232)) ([3a9a8b2](https://github.com/devantler-tech/actions/commit/3a9a8b2f7e0f761853926895ce3d1269af402bea))
* grant release-please the workflows scope for self-pin rewrites ([#337](https://github.com/devantler-tech/actions/issues/337)) ([ea68e2b](https://github.com/devantler-tech/actions/commit/ea68e2b38262a6b3a2c67a76996da63a6e8e7e82))
* guard ci.yaml test wiring and fix silently-ignored free-disk-space results ([#355](https://github.com/devantler-tech/actions/issues/355)) ([16239bb](https://github.com/devantler-tech/actions/commit/16239bb3b5174452d8d44b98ec26e9d244781dbe))
* scan main on push so code-scanning baseline stays current ([#275](https://github.com/devantler-tech/actions/issues/275)) ([eeb1b95](https://github.com/devantler-tech/actions/commit/eeb1b956da3ff6e18f6adb26821b3df60d531783))
* skip CI suite and dependency-review on release-please PRs ([#359](https://github.com/devantler-tech/actions/issues/359)) ([7f215f7](https://github.com/devantler-tech/actions/commit/7f215f7816adbbbc6beaba5248c5b3f9a1b91dfa))
* skip the suite on the release-commit push to dodge the self-pin tag race ([#412](https://github.com/devantler-tech/actions/issues/412)) ([91efa53](https://github.com/devantler-tech/actions/commit/91efa53fa80d71341e1546510316b18722da79f5))
* switch from Renovate to Dependabot ([#50](https://github.com/devantler-tech/actions/issues/50)) ([f1fcdf7](https://github.com/devantler-tech/actions/commit/f1fcdf7dd14ab98198c2965e222a9481098bc430))

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
