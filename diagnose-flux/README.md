# Diagnose Flux on failure

Dump Flux reconcile state, controller logs, and failing/CrashLooping pod logs to
debug a stuck Flux deploy in CI/CD. When a system-test or prod deploy fails, the
useful signal is spread across the Flux CRs (`Kustomization` / `HelmRelease` /
`OCIRepository` status), the `flux-system` controller logs, and the logs of
whatever pod is actually crash-looping — and a `CrashLoopBackOff` pod stays in
`phase=Running` with `waiting.reason=CrashLoopBackOff`, so naively filtering on
phase misses it. This action gathers all of that into grouped log sections in
one step.

It is **best-effort** (`set +e`): it never fails the calling step itself, so a
transient `kubectl`/`jq` hiccup can't mask the original failure. Gate it with
`if: failure()` on the caller so it only runs when the deploy/test step failed.

> **Assumes `kubectl` is already configured** for the target cluster (the calling
> job has set up the kubeconfig/context) and that `jq` is available — both are
> present on the GitHub-hosted `ubuntu-latest` runner image.

## Inputs

| Name | Description | Required | Default |
|------|-------------|----------|---------|
| `kustomizations` | Space-separated Flux Kustomization names (in `flux-system`) to `describe` on failure | ❌ | `infrastructure-controllers infrastructure apps` |

## Usage

### Diagnose a failed Flux deploy

```yaml
steps:
  - name: 🚀 Deploy
    run: ksail up # …or whatever drives the Flux reconcile

  - name: 🩺 Diagnose Flux on failure
    if: failure()
    uses: devantler-tech/actions/diagnose-flux@main
```

### Describe a different set of Kustomizations

```yaml
steps:
  - name: 🩺 Diagnose Flux on failure
    if: failure()
    uses: devantler-tech/actions/diagnose-flux@main
    with:
      kustomizations: infrastructure apps tenants
```
