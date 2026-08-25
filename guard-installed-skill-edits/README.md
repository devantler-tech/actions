# Guard Installed Skill Edits

Refuse a hand-edit to a synced installed-skill tree and name the skill's
upstream so the change is made there instead of being silently reverted.

The check keys on `metadata.github-repo` in each skill's `SKILL.md` at the pull
request **base**, not on the current path. Provenance must be a **direct child**
of the `metadata` mapping: a top-level `github-repo`, or one nested deeper such
as `metadata.source.github-repo`, is not provenance and does not mark a skill as
synced — otherwise a stray key could make a local skill permanently uneditable.
Adding a wholly new skill directory is allowed, and so is retiring one wholesale:
removing an installed skill is a local decision, and only editing a synced one is
not. The programmed `update-agent-skills` PR is exempt only when both the actor
and the head branch match. Missing CI context, an unreadable `SKILL.md`, or
provenance that cannot be READ is UNKNOWN rather than a silent pass. A record that reads cleanly and simply names no upstream means the skill is local, and a local skill stays editable.

Changed paths come from the **merge base** (a three-dot diff), not from the two
commits directly. A base branch that advances after a PR branches — most often
the daily updater editing a synced skill — would otherwise be attributed to the
PR, and the guard would refuse a pull request that never touched that skill.

## Requirements

The guard needs **both the base and head commits present locally**. The default
`actions/checkout` fetches depth 1, so the base commit is absent and the diff
cannot be computed; give the checkout enough history (`fetch-depth: 0`, or fetch
the base ref explicitly). When the diff cannot be computed the guard reports
UNKNOWN and fails — it never treats an unreadable diff as "nothing changed".

`merge_group` is supported: that event carries no `pull_request` object, so the
SHAs fall back to `github.event.merge_group.base_sha` / `head_sha`. Note that a
merge-queue run carries no PR identity, so the programmed-sync exemption cannot
be evaluated there — a consumer whose updater PR passes through a merge queue
should exempt that lane at the workflow level.

## Inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `skill-root` | Repository-relative installed-skill root | no | `.agents/skills` |
| `sync-actor` | Exact GitHub login of the programmed updater App | no | `botantler-1[bot]` |
| `sync-branch` | Exact head-branch name of the programmed updater PR | no | `deps/agent-skills-update` |

## Outputs

This action has no outputs.

## Usage

The checkout is part of the usage, not a precondition you can assume: with no checkout the
action sees no skill root and exits 0 without checking anything, which turns the guard into a
silent no-op. `fetch-depth: 0` is what makes the base commit available to the diff.

```yaml
- name: ⬇️ Checkout
  uses: actions/checkout@<sha> # <version>
  with:
    fetch-depth: 0

- name: Guard installed skill edits
  uses: devantler-tech/actions/guard-installed-skill-edits@<sha> # <version>
```

Pass a different `skill-root` when the consumer installs skills somewhere other than
`.agents/skills`. A leading `./`, a trailing `/`, or `.` for skills at the repository root are all accepted and normalised.


