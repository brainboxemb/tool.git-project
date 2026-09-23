# Moon affected preflight

`tool.git-project` provides a domain-neutral host-side impact check for repositories that need to know which configured Moon work is affected **before** starting an expensive domain runtime or container.

The check uses Moon's own VCS/task-input/graph model. It does not maintain a second list of file patterns in GitHub Actions and it does not execute producer tasks.

## Results

One Moon affected query now serves two callers at once:

1. the existing compatibility decision for one requested target (`true`/`false`);
2. the complete normalized list of affected Moon task IDs from that same query.

The task list is useful to a domain layer that has several coarse capabilities and wants one expensive runtime invocation to execute only the capabilities that actually changed.

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

The command keeps its original stdout contract and writes exactly one normal result:

```text
true
```

or:

```text
false
```

`true` means the requested target is affected **or** the query could not safely prove that it is unaffected. That conservative behavior is intentional: an impact-check problem must not silently suppress required production work.

The complete affected task list is written separately to:

```text
.moon/preflight/affected-task-ids.json
```

Example:

```json
["consumer:scad.build","consumer:scad.docs"]
```

The list is lexically sorted and contains fully-qualified Moon task IDs. It is derived from the same `moon query tasks --affected --downstream deep` result used for the boolean; Moon is not invoked once per task.

When no task is affected, the list is `[]`.

When the check falls back conservatively because revisions, configuration, Moon bootstrap/querying or result parsing cannot be trusted:

- the compatibility decision remains `true`;
- `decision.json` records `"status": "conservative"`;
- `affected-task-ids.json` remains `[]` because a trustworthy precise list is unavailable.

A domain layer that consumes the list must therefore treat `status=conservative` as “run the safe full requested scope”, not as “nothing is affected”.

## GitHub Actions composite action

Consumers normally call the released action from a lightweight host job:

```yaml
jobs:
  impact:
    runs-on: ubuntu-24.04
    outputs:
      affected: ${{ steps.affected.outputs.affected }}
      affected_tasks: ${{ steps.affected.outputs.affected-tasks }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
        with:
          fetch-depth: 0
          filter: blob:none

      - id: affected
        uses: brainboxemb/tool.git-project/moon/affected@<released-version>
        with:
          task: consumer:scad.ci
          base: ${{ github.event.pull_request.base.sha }}
          head: ${{ github.sha }}

  expensive-domain-job:
    needs: impact
    if: needs.impact.outputs.affected == 'true'
    # Domain tooling may now select its runtime and pass the JSON task list
    # to one execution invocation. Domain policy decides how conservative
    # fallback maps to its full safe capability scope.
```

Action outputs:

| Output | Meaning |
| --- | --- |
| `affected` | Existing compatibility boolean for the requested target, including conservative `true` fallback. |
| `affected-tasks` | Compact JSON array of fully-qualified affected Moon task IDs from the same successful query; `[]` for no affected tasks or conservative fallback. |
| `evidence-directory` | Configured evidence directory. |

The calling workflow remains responsible for choosing the correct event-specific base/head revisions. Pull-request, push, release and manual workflows do not necessarily use the same comparison pair.

## Evidence

Each query writes diagnostic evidence under `.moon/preflight` by default:

```text
.moon/preflight/
  decision.json
  task.json
  changed-files.json
  affected-tasks.json
  affected-task-ids.json
  *.log
```

`affected-tasks.json` is Moon's complete query output and remains the authoritative detailed diagnostic record.

`affected-task-ids.json` is a stable compact normalization for orchestration consumers.

`decision.json` records:

- Moon version;
- requested fully-qualified task;
- base/head revisions;
- final affected decision;
- whether that decision was a normal successful query or a conservative fallback;
- a short reason.

This is impact/orchestration evidence. It is **not** producer execution evidence and must not be presented as proof that the domain build/test ran.

## Ownership boundary

`tool.git-project` owns only:

- the pinned Moon runtime;
- explicit base/head VCS query mechanics;
- Moon task affected queries;
- generic boolean/list/evidence output;
- conservative failure behavior.

It does not understand SCAD, Java, Maven, SCons, documentation generation or other domain configuration. A domain owner supplies Moon tasks whose declared inputs and graph encode the relevant repository responsibilities, and decides which affected task IDs correspond to its own capabilities.

## Qualification contract

The owner regression uses real Moon 2.5.4 and real Git commits to prove on Linux and Windows that:

1. a README-only change outside fixture task inputs returns `affected=false` and `[]`;
2. an independent committed input change returns exactly one affected task ID;
3. a task-input change with a downstream aggregate returns multiple sorted affected task IDs;
4. the check never executes the producer command;
5. an unavailable base revision produces conservative `affected=true` plus an empty precise list;
6. base/head revisions are explicit rather than inferred by the wrapper;
7. the composite action exposes the same compact list that is retained in evidence.

The separate normal Moon regression continues to qualify execution, cache hits and hydration. The affected check only reports impact; it does not replace Moon execution/materialization or a domain engine's own finer-grained decisions.
