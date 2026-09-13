# Moon repository orchestration

`tool.git-project` provides an optional Moon integration for repositories that want faster build and release feedback by avoiding unnecessary domain execution and restoring reusable outputs from cache.

Moon is **not** part of the basic Git bootstrap path. `git-project.sh` / `git-project.ps1` remain Git-only. Repositories opt into Moon through `moon-project.sh`, `moon-project.ps1`, or the composite action at `moon/action.yml`.

## Ownership boundary

```text
Git / CI event
      |
      v
tool.git-project Moon integration
  pinned runtime / cache restore / invocation evidence
      |
      v
Moon task graph / hashing / output hydration
      |
      v
domain action
  tool.java-project / tool.scad-project / tool.eng-docs / repository validator
```

`tool.git-project` does not implement its own scheduler, hasher, affected-selection engine, or output cache. Moon owns those mechanisms. Domain tools remain authoritative for their build/test semantics and domain evidence.

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

Exact domain commands and outputs belong to the domain owner/consumer contract. The generic Moon integration only invokes the declared target.

`moon-project validate` verifies the pinned runtime, expected repository files, Git worktree, and asks Moon to parse the configured project graph without running a domain build.

## GitHub Actions

Moon's affected/change model needs complete commit history. To keep that checkout efficient, use a blobless full-history checkout:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
  with:
    fetch-depth: 0
    filter: blob:none
```

Then call the released composite action:

```yaml
- uses: brainboxemb/tool.git-project/moon@v0.2.0
  with:
    task: consumer:java.canonical
    cache-namespace: java-canonical
```

The action owns two reusable caches:

1. the pinned Moon runtime, so normal CI runs do not repeatedly download it;
2. Moon's portable task cache:
   - `.moon/cache/hashes`
   - `.moon/cache/outputs`

The task cache key includes Moon version, runner OS, caller namespace, run ID, and run attempt. Restore keys intentionally allow an earlier compatible cache for the same Moon version/OS/namespace; Moon still decides whether a restored entry matches current task inputs.

## Evidence model

There are two different kinds of evidence and they must not be conflated.

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
- caches the pinned Moon runtime separately;
- restores Moon's portable output/hash cache on fresh CI runners;
- delegates input hashing, task selection, and hydration to Moon;
- keeps domain actions coarse enough to avoid duplicating Maven/SCons internal lifecycle work;
- uses blobless full Git history for correct affected detection without eagerly downloading every repository blob.

If a future extension does not help task selection, cache reuse, output hydration, or release/build feedback time, it should not be added to this layer merely for architectural symmetry.
