# Free Disk Space

Reclaim runner disk by removing large preinstalled toolchains a job never uses
(Android SDK, .NET, GHC, …). GitHub-hosted `ubuntu-latest` runners ship ~14 GB
free on `/`; a large module's `go build` / `go test ./...` build cache (and the
coverage job's `-race` binaries) can exhaust it, producing a hard
`No space left on device` failure. This action reclaims ~11+ GB with targeted
`rm -rf` only — it avoids the slow `apt-get remove` path and is best-effort
(a missing path is never an error).

Each toolchain is removed by default and can be kept by setting its input to
`false` (e.g. a job that runs `.NET` should pass `dotnet: "false"`).

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `android` | Remove the Android SDK (/usr/local/lib/android, ~9 GB) | ❌ | `true` |
| `dotnet` | Remove the .NET SDK (/usr/share/dotnet) | ❌ | `true` |
| `haskell` | Remove GHC / Haskell (/opt/ghc) | ❌ | `true` |
| `boost` | Remove the Boost C++ libraries (/usr/local/share/boost) | ❌ | `true` |
| `swift` | Remove the Swift toolchain (/usr/share/swift) | ❌ | `true` |
| `codeql` | Remove the CodeQL tool cache (/opt/hostedtoolcache/CodeQL) | ❌ | `true` |
| `pypy` | Remove the PyPy tool cache (/opt/hostedtoolcache/PyPy) | ❌ | `true` |
| `powershell` | Remove PowerShell (/usr/local/share/powershell) | ❌ | `true` |
| `miniconda` | Remove Miniconda (/usr/share/miniconda) | ❌ | `true` |

## Outputs

| Name | Description |
|------|-------------|
| `freed` | Approximate gigabytes of disk space reclaimed on / |
| `available` | Gigabytes available on / after reclaiming |

## Usage

### Reclaim before a Go build/test

```yaml
steps:
  - name: Free disk space
    uses: devantler-tech/actions/free-disk-space@main

  - name: Setup Go
    uses: devantler-tech/actions/setup-go-toolchain@main

  - name: Test
    shell: bash
    run: go test ./...
```

### Keep a toolchain the job needs

```yaml
steps:
  - name: Free disk space
    uses: devantler-tech/actions/free-disk-space@main
    with:
      dotnet: "false" # job runs .NET — keep /usr/share/dotnet
```

### Read how much was reclaimed

```yaml
steps:
  - name: Free disk space
    id: disk
    uses: devantler-tech/actions/free-disk-space@main

  - name: Report
    shell: bash
    env:
      FREED: ${{ steps.disk.outputs.freed }}
      AVAILABLE: ${{ steps.disk.outputs.available }}
    run: echo "Reclaimed ${FREED}G; ${AVAILABLE}G now free."
```
