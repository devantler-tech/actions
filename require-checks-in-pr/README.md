# Require Checks in PR

A GitHub composite action that aggregates the results of multiple jobs into a single required check. Fails if any job failed or was cancelled. Useful for branch protection rules that need a single, stable check name.

## Why?

GitHub branch protection rules require a specific check to pass. When using matrix builds or conditional jobs, the check names can vary (e.g., `build (ubuntu, go-1.21)`, `build (macos, go-1.22)`). This action provides a single, stable check name that reports the aggregate status of all jobs.

## Usage

```yaml
jobs:
  build:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - run: echo "Building..."

  test:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: echo "Testing..."

  ci-required-checks:
    name: CI - Required Checks
    runs-on: ubuntu-latest
    needs: [build, test]
    if: ${{ always() }}
    steps:
      - uses: devantler-tech/actions/require-checks-in-pr@1f66c91d45d374ceac9fe830a783444ebc9be958 # v3.2.0
        with:
          job-results: |
            ${{ needs.build.result }}
            ${{ needs.test.result }}
```

## Inputs

| Input        | Description                                                | Required | Default                |
| ------------ | ---------------------------------------------------------- | -------- | ---------------------- |
| `job-results` | Newline-separated list of job results to check            | Yes      | —                      |
| `check-name`  | Display name used in success/failure messages             | No       | `CI - Required Checks` |

## Job Result Values

| Result      | Description                         | Treated as |
| ----------- | ----------------------------------- | ---------- |
| `success`   | Job completed successfully          | ✅ Pass     |
| `skipped`   | Job was skipped (condition not met) | ✅ Pass     |
| `failure`   | Job failed                          | ❌ Fail     |
| `cancelled` | Job was cancelled                   | ❌ Fail     |

## Custom Check Name

```yaml
  ci-ksail:
    name: CI - KSail
    runs-on: ubuntu-latest
    needs: [build, lint, test]
    if: ${{ always() }}
    steps:
      - uses: devantler-tech/actions/require-checks-in-pr@1f66c91d45d374ceac9fe830a783444ebc9be958 # v3.2.0
        with:
          job-results: |
            ${{ needs.build.result }}
            ${{ needs.lint.result }}
            ${{ needs.test.result }}
          check-name: CI - KSail
```
