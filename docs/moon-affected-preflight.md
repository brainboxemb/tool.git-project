# Moon affected preflight

`tool.git-project` provides a domain-neutral host-side preflight for repositories that need to know whether a configured Moon task is affected **before** starting an expensive domain runtime or container.

The preflight uses Moon's own VCS/task-input/graph model. It does not maintain a second list of file patterns in GitHub Actions and it does not execute the producer task.

## Command line

Linux:

```bash
bash tools/tool.git-project/moon-affected.sh \
  consumer:scad.ci \
  --repo . \
  --base "$BASE_REV" \
  --head "$HEAD_REV"
```

Windows:

```powershell
.\tools\tool.git-project\moon-affected.ps1 `
  'consumer:scad.ci' `
  -Repo . `
  -Base $BaseRevision `
  -Head $HeadRevision
```

The command writes exactly one normal result to stdout:

```text
true
```

or:

```text
false
```

`true` means the task is affected **or** the query could not safely prove that it is unaffected. That conservative behavior is intentional: a preflight problem must not silently suppress required production work.

## GitHub Actions composite action

Consumers normally call the released action from a lightweight host job:

```yaml
jobs:
  preflight:
    runs-on: ubuntu-24.04
    outputs:
      affected: ${{ steps.affected.outputs.affected }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          fetch-depth: 0
          filter: blob:none

      - id: affected
        uses: brainboxemb/tool.git-project/moon/affected@v0.2.5
        with:
          task: consumer:scad.ci
          base: ${{ github.event.pull_request.base.sha }}
          head: ${{ github.sha }}

  expensive-domain-job:
    needs: preflight
    if: needs.preflight.outputs.affected == 'true'
    # Domain tooling may now select its container/runtime.
```

The calling workflow remains responsible for choosing the correct event-specific base/head revisions. Pull-request, push, release and manual workflows do not necessarily use the same comparison pair.

## Evidence

Each query writes diagnostic evidence under `.moon/preflight` by default:

```text
.moon/preflight/
  decision.json
  task.json
  changed-files.json
  affected-tasks.json
  *.log
```

`decision.json` records:

- Moon version;
- requested fully-qualified task;
- base/head revisions;
- final affected decision;
- whether that decision was a normal successful query or a conservative fallback;
- a short reason.

This is preflight/orchestration evidence. It is **not** producer execution evidence and must not be presented as proof that the domain build/test ran.

## Ownership boundary

`tool.git-project` owns only:

- the pinned Moon runtime;
- explicit base/head VCS query mechanics;
- Moon task affected queries;
- generic decision/evidence output;
- conservative failure behavior.

It does not understand SCAD, Java, Maven, SCons, documentation generation or other domain configuration. A domain owner supplies the Moon task whose declared inputs and graph encode the relevant repository responsibilities.

## Qualification contract

The owner regression uses real Moon 2.5.4 and real Git commits to prove on Linux and Windows that:

1. a README-only change outside a fixture task's inputs is unaffected;
2. a committed task-input change is affected;
3. the preflight never executes the producer command;
4. an unavailable base revision produces a conservative `true` decision;
5. base/head revisions are explicit rather than inferred by the wrapper.

The separate normal Moon regression continues to qualify execution, cache hits and hydration. The preflight only answers whether a task is affected; it does not replace Moon execution/materialization or a domain engine's own finer-grained decisions.
