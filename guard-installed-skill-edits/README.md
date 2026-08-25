# Guard Installed Skill Edits

Refuse a hand-edit to a synced installed-skill tree and name the skill's
upstream so the change is made there instead of being silently reverted.

The check keys on provenance recorded in each skill's `SKILL.md` at the
pull request **base**, not on the current path. A wholly new skill directory
is allowed. The programmed `update-agent-skills` PR is exempt only when both
the actor and the head branch match. Missing CI context is UNKNOWN rather
than a silent pass.

## Inputs

| Input | Description | Required | Default |
| --- | --- | --- | --- |
| `skill-root` | Repository-relative installed-skill root | no | `.agents/skills` |
| `sync-actor` | Exact GitHub login of the programmed updater App | no | `botantler-1[bot]` |
| `sync-branch` | Exact head-branch name of the programmed updater PR | no | `deps/agent-skills-update` |

## Outputs

This action has no outputs.

## Usage

```yaml
- name: Guard installed skill edits
  uses: devantler-tech/actions/guard-installed-skill-edits@<sha> # <version>
```

Pass a different `skill-root` when the consumer installs skills somewhere
other than `.agents/skills`.
