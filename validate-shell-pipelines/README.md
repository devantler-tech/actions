# Validate shell pipelines

Find shell assertions that can lose a producer's exit status when `grep` stops
reading a pipe early. This action is being delivered behind a temporary opt-in;
consumer validation and retirement of that input are tracked in
[#1357](https://github.com/devantler-tech/actions/issues/1357).

Actions opts its own required CI into this guard for `.scripts`, `.github/scripts`,
`.github/tests`, `guard-installed-skill-edits`, and `update-agent-skills`. This
covers its real helpers and their tests. Deliberately invalid product fixtures
under `.github/fixtures` belong to the separate positive/negative action tests.
The adoption regression test reads CI's actual scope and injects a finding into
a disposable copy from each selected directory; it never executes those scripts.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `enabled` | Opt in to validation; accepts exactly `true` or `false`. | No | `false` |
| `working-directory` | Git checkout directory, relative to `GITHUB_WORKSPACE` or absolute. | No | `.` |
| `paths` | Newline-separated relative files or directories; each must include at least one tracked shell file. | No | `.` |

## Outputs

| Name | Description |
|------|-------------|
| `validated` | `true` after a complete successful scan; empty when disabled or unsuccessful. |

## Usage

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
    with:
      persist-credentials: false
  - uses: devantler-tech/actions/validate-shell-pipelines@<full-commit-sha>
    with:
      enabled: "true"
      paths: |
        scripts
        .github/tests
```

Omitting `paths` scans the checkout. Paths are literal, relative to
`working-directory`, and must be clean: no absolute paths, `..`, `./`, or
backslashes. Glob syntax has no special meaning. Empty lines are ignored; an
entirely empty input is an error. Overlapping scopes scan each file once.

Discovery selects Git-tracked `.sh` and `.bash` files, plus files with a direct
`sh`/`bash`, `env sh`/`env bash`, or `env -S sh`/`env -S bash` shebang. It reads
their current working-tree content. Untracked files are excluded and submodules
are not traversed. Symlinks in the selected tracked paths, missing files, unmerged
index entries, and unreadable paths fail the scan. Each shell file is limited to
16 MiB. A scope containing no tracked shell files fails, including a misspelled
path or a scope containing only submodules.

Enabled runs install the Go version in this action's `go.mod` and download its
checksum-pinned shell parser with bounded retries. These build steps need network
access to the Go distribution and module services. Subsequent validation is
offline; it neither modifies nor executes the scanned scripts. Linux and macOS
runners are supported. Omitted or false enablement skips all setup and discovery.

## What it catches

With `set -o pipefail`, a successful early match can close the pipe while the
producer is still writing. The producer then fails with SIGPIPE and the pipeline
is unsuccessful even though `grep` matched. Negating that pipeline can make a
negative assertion pass incorrectly.

```bash
# Unsafe: a match may still produce a nonzero pipeline status.
producer | grep -q needle

# Safe for bounded output: capture and check the producer before searching.
captured=$(producer) || exit "$?"
grep -q needle <<< "$captured"
```

For large output, capture to a temporary file and check the producer's status
before searching the file; clean it up with a trap. Process substitution alone
does not preserve the producer's exit status. Plain `grep` without early-exit
options is another option when its output is appropriate for the caller.

The guard reports `-q`, `--quiet`, `--silent`, `-l`, `--files-with-matches`, and
count limits (`-m`, `--max-count`). Literal `-1` means unlimited and is excluded.
It handles short-option clusters, option arguments, options after the pattern,
`--`, literal quoting/escaping, line continuations, assignments, `|&`, negation,
and pipelines inside command substitutions. It also recognizes ordinary `command`
and `env` wrappers and a single command inside a subshell or brace group.

Quoted examples, comments, and literal heredoc text are ignored. Executable
command substitutions inside unquoted heredocs are inspected. Parsing uses Bash
syntax, which covers ordinary POSIX shell scripts; invalid or unsupported syntax
fails with exit 2 and does not print the source excerpt.

## Exceptions and limits

For an intentional negative fixture or an independently verified bounded producer,
use an actual shell comment with a reason:

```bash
producer | grep -q needle # pipefail-grep-guard: allow intentional SIGPIPE fixture
```

`allow` applies to a comment on a line occupied by the receiving command, including
its continued arguments. A file-wide exception uses
`# pipefail-grep-guard: allow-file <reason>`. Both require a reason; misspelled or
empty directives fail. A marker in a quoted string or heredoc never grants an
exception. Exceptions do not bypass syntax, discovery, or read checks.

This is a static guard for direct syntactic pipelines, not shell data-flow
analysis. It does not resolve aliases, function bodies invoked as the receiver,
variables that supply the command or flags, `eval`, ANSI/localized dollar quotes,
`env --split-string`, or a receiving group containing multiple commands. Unsupported
wrapper forms are not interpreted. Explicit early-exit flags are conservative:
the guard does not prove small output, runtime option precedence, platform-specific
grep behavior, or that `pipefail` is disabled in every caller. A clean result only
means no supported unsafe form was found in the selected files.

## Local validation

```bash
GOWORK=off go -C /path/to/actions/validate-shell-pipelines run -mod=readonly . \
  --root /path/to/consumer --paths scripts

go -C validate-shell-pipelines test -race -cover ./...
go -C validate-shell-pipelines vet ./...
```

The CLI exit codes are `0` (complete clean scan), `1` (unsafe pipelines), and `2`
(invalid arguments, scope, Git discovery, filesystem access, exceptions, or shell
syntax). Diagnostics print quoted filenames, line numbers, the unsafe option,
and repair guidance, without pattern values or source text.

## Design

The validator parses tracked Bash/POSIX shell files with the checksum-pinned
`mvdan.cc/sh/v3` syntax parser. It inspects shell syntax without running the
scripts, expanding variables, or interpreting aliases and functions. Git supplies
the tracked file set; discovery, scope, read, and parse failures are errors rather
than an empty successful scan. Quoted prose and comments are not commands.

Early-exit `grep` flags on a pipeline's receiving command are reported regardless
of whether `pipefail` is set locally: a caller may enable it before sourcing the
file. Diagnostics identify the path, line, option, and repair without printing
the source text. Exceptions must be actual shell comments with a reason.

The action builds its own Go module independently of the caller's module. Its
default-disabled path does not discover files, install Go, or download modules.
The CLI always performs validation and uses exit codes 0 (clean), 1 (findings),
and 2 (incomplete or invalid scan).
