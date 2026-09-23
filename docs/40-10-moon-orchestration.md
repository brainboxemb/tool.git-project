# Moon repository orchestration

`tool.git-project` provides an optional Moon integration for repositories that want faster build and release feedback by avoiding unnecessary domain execution and restoring reusable outputs from cache.

Moon is **not** part of the basic Git bootstrap path. `git-project.sh` / `git-project.ps1` remain Git-only. Repositories opt into Moon through `moon-project.sh`, `moon-project.ps1`, or the composite actions under `moon/`.

## Ownership boundary

```text
Git / CI event
      |
      v
tool.git-project Moon integration
  pinned runtime / affected query / cache restore / invocation evidence
      |
      v
Moon task graph / hashing / affected selection / output hydration
      |
      v
domain action
  tool.java-project / tool.scad-project / tool.eng-docs / repository validator
```

`tool.git-project` does not implement its own scheduler, hasher, affected-selection engine, dependency graph, or output cache. Moon owns those mechanisms. Domain tools remain authoritative for their build/test semantics and domain evidence.

## Pinned runtime

The production baseline is Moon `2.5.4`. Linux and Windows download URLs plus SHA-256 digests are source-controlled in `moon/runtime.env`.

Local commands:

```bash
./moon-project.sh bootstrap
./moon-project.sh validate --repo .
./moon-project.sh cache-paths --repo .
./moon-project.sh run consumer:java.canonical --repo .
```

PowerShell equivalents use `moon-project.ps1`.

The bootstrap command reuses an already-correct `MOON_BIN`, an already-correct Moon on `PATH`, or the previously installed pinned runtime before downloading anything.

On Linux, the pinned runtime archive is SHA-256 verified before extraction. Normal hosts use `tar` with the external `xz` executable. Minimal containers that do not provide `xz` automatically fall back to Python 3 when its standard `lzma` and `tarfile` modules are available. If neither extraction path is available, bootstrap fails with an explicit prerequisite error instead of failing indirectly inside `tar`.

## Repository configuration

Consumers use Moon's own configuration instead of a parallel `project.build.yml` model.

Minimal workspace example:

```yaml
# .moon/workspace.yml
projects:
  consumer: '.'

vcs:
  client: git
  provider: github
  defaultBranch: main

telemetry: false

pipeline:
  installDependencies: false
  syncProjects: false
  syncWorkspace: false
```

A Java-shaped task can bind directly to the stable domain action:

```yaml
# moon.yml
tasks:
  java.canonical:
    command: 'bash tools/tool.java-project/java-project.sh canonical'
    inputs:
      - 'project.yml'
      - 'project.java.yml'
      - 'pom.xml'
      - 'mvnw'
      - 'mvnw.cmd'
      - '.mvn/**'
      - 'src/main/**'
      - 'src/test/**'
      - 'tools/tool.java-project/**'
    outputs:
      - 'bld/**'
    options:
      cache: true
```

Exact domain commands and outputs belong to the domain owner/consumer contract. The generic Moon integration only invokes or queries the declared task graph.

`moon-project validate` verifies the pinned runtime, expected repository files, Git worktree, and asks Moon to parse the configured project graph without running a domain build.

## Affected preflight

The released affected interface accepts a fully-qualified target plus explicit VCS base and head revisions. It asks a repository-level question:

> Would executing this target traverse any task that Moon considers affected for this exact base-to-head change?

This matters for aggregate tasks. An aggregate can have no changed direct inputs while one of its dependencies is affected. The preflight therefore lets Moon compute the complete affected set and propagate it through the task graph to deep downstream dependents, then checks whether the requested target is present in that Moon result.

The generic layer does not duplicate task dependencies or maintain a changed-path table.

A normal unaffected query returns `false`. Query/bootstrap/revision uncertainty fails conservative and returns `true`, so an expensive domain job is run rather than silently skipped.

The query writes evidence under `.moon/preflight` by default:

```text
changed-files.json
affected-tasks.json
task.json
decision.json
*.log
```

The query never executes the producer task.

## Minimal explicit base/head checkout

An explicit affected preflight does **not** require `fetch-depth: 0`.

Moon 2.5.4 has been qualified with two exact shallow history roots:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
  with:
    ref: ${{ env.HEAD_SHA }}
    fetch-depth: 1
    filter: blob:none
    submodules: false

- shell: bash
  run: git fetch --no-tags --depth=1 origin "$BASE_SHA"
```

The qualification proves that the explicit `changed-files --base <sha> --head <sha>` query works when:

- both exact commits are available;
- both are shallow history roots;
- intervening history is not traversable locally.

This is the preferred shape for a lightweight pre-container gate because it avoids downloading unrelated branch/tag history and avoids initializing domain submodules before impact is known.

Full history can still be appropriate for workflows that deliberately rely on implicit VCS ranges, merge-base discovery, ancestry traversal, or other operations beyond the explicit two-tree affected contract. Do not generalize the minimal preflight checkout to those different use cases without qualification.

## GitHub Actions

For a host-side gate, call the affected composite action after the exact revisions are locally available:

```yaml
- id: affected
  uses: brainboxemb/tool.git-project/moon/affected@<exact-release-commit>
  with:
    task: consumer:scad.ci
    base: ${{ env.BASE_SHA }}
    head: ${{ env.HEAD_SHA }}
```

For production/cache execution, call the Moon production action:

```yaml
- uses: brainboxemb/tool.git-project/moon@<exact-release-commit>
  with:
    task: consumer:java.canonical
    cache-namespace: java-canonical
```

The production action owns two reusable caches:

1. the pinned Moon runtime, so normal CI runs do not repeatedly download it;
2. Moon's portable task cache:
   - `.moon/cache/hashes`
   - `.moon/cache/outputs`

The task cache key includes Moon version, runner OS, caller namespace, run ID, and run attempt. Restore keys intentionally allow an earlier compatible cache for the same Moon version/OS/namespace; Moon still decides whether a restored entry matches current task inputs.

## Evidence model

There are three distinct evidence layers and they must not be conflated.

### Affected-query evidence

The host preflight records current base/head, changed files, Moon's affected task set and the final conservative/success decision under `.moon/preflight`.

### Producer evidence

Evidence created by the domain action belongs inside the task's declared outputs. If Moon hydrates an old reusable output, that evidence continues to describe the original producer execution.

### Materialization / invocation evidence

Each `moon-project run` records current orchestration context under:

```text
.moon/invocations/<task>/
  moon.log
  materialization.json
```

The JSON records the current source revision, Moon version, requested task, final status, exit code, and invocation duration. It does not rewrite cached producer evidence to pretend a domain build ran again.

## Performance intent

This integration exists to shorten feedback cycles. The production path therefore deliberately:

- keeps ordinary Git bootstrap independent from Moon;
- allows exact shallow/blobless base/head checkout for an explicit affected preflight;
- avoids domain dependency/submodule setup until the affected gate says work is needed;
- caches the pinned Moon runtime separately;
- restores Moon's portable output/hash cache on fresh CI runners;
- delegates input hashing, affected propagation, task selection and hydration to Moon;
- keeps domain actions coarse enough to avoid duplicating Maven/SCons internal lifecycle work.

If a future extension does not help task selection, cache reuse, output hydration, or release/build feedback time, it should not be added to this layer merely for architectural symmetry.
