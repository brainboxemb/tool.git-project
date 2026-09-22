# tool.git-project

Reusable generic repository tooling for Git dependency bootstrap, pinned external repositories, repository lifecycle operations, and optional Moon build orchestration.

`tool.git-project` owns the generic repository mechanism shared by Java, SCAD, documentation, and future engineering projects. Its **core Git path remains Git-only**. Moon is an explicit opt-in capability for repositories that want faster build/release feedback through high-level task selection and output-cache hydration. The tool deliberately does **not** own Java/Maven, OpenSCAD/SCons, documentation-rendering, Docker, or product-domain behaviour.

Release history: [`CHANGELOG.md`](CHANGELOG.md)

## Model

A consumer keeps generic repository/dependency information in `project.yml` and keeps build-system-specific settings in profile files such as `project.java.yml` or `project.scad.yml`.

```text
committed gitlink: tools/tool.git-project
  bootstrap engine itself, pinned directly by Git
       |
       v
project.yml
  project metadata
  profiles -> project.<profile>.yml
  dependencies[]
       |
       v
tool.git-project
  Git-only validate / bootstrap / status / update
  generic Git lifecycle workflows
  optional Moon orchestration companion
       |
       +--> managed Git submodules / pinned refs
       +--> Moon high-level task/cache/hydration layer

project.java.yml  -> tool.java-project
project.scad.yml  -> tool.scad-project
```

The Git tool validates that configured profile files exist, but treats their contents as opaque. Moon-enabled repositories keep their task graph in Moon's own `.moon/workspace.yml` and `moon.yml`; `tool.git-project` does not invent a second task-graph format.

## Tool release baseline

`VERSION` is the source-controlled release version of `tool.git-project`. Reusable GitHub workflows/actions are released together with the normal Git tooling and are consumed through an immutable release tag, never through moving `main`.

For maximum reproducibility a consumer may additionally record or pin the exact commit behind the release tag in its committed gitlink/provenance. A normal release is created only from the exact current `main` commit after the required self-tests are green.

Generic release-request, tag and optional release orchestration is documented in [`docs/release-lifecycle.md`](docs/release-lifecycle.md).

## Bootstrap dependency

`tool.git-project` is intentionally **not listed as a dependency in its own `project.yml` model**. It is the bootstrap engine required before that model can be processed.

A consumer pins it directly through the committed Git submodule/gitlink at:

```text
tools/tool.git-project
```

That gives a normal clean clone an exact bootstrap-tool commit without recursive self-management. The root `bootstrap.ps1` / `bootstrap.sh` launchers restore that exact pinned commit and then delegate to the pinned tool.

When creating a new consumer repository, register this bootstrap dependency once, checkout the desired tool commit/tag, and commit both `.gitmodules` and the gitlink. After that every clone is deterministic.

## Generic dependency example

```yaml
schema_version: 1

project:
  name: my-project

profiles:
  - type: java
    config: project.java.yml

dependencies:
  - name: tool.java-project
    role: tooling
    type: git-submodule
    url: https://github.com/brainboxemb/tool.java-project.git
    path: tools/tool.java-project
    ref: v0.1.2
```

See [`docs/project-format.md`](docs/project-format.md) for the contract.

## Local Git commands

PowerShell / Windows:

```powershell
.\git-project.ps1 validate
.\git-project.ps1 bootstrap
.\git-project.ps1 status
.\git-project.ps1 update
```

POSIX shell:

```bash
./git-project.sh validate
./git-project.sh bootstrap
./git-project.sh status
./git-project.sh update
```

The commands can also operate on another local repository, which is useful for CI and tooling tests.

### Command semantics

- `validate` — parse and validate generic `project.yml`; verify referenced profile files exist.
- `bootstrap` — register/repair declared direct submodules, align them to configured refs, then complete the controlled transitive closure of nested `role: external` git-submodule dependencies.
- `status` — inspect direct state plus nested external owner/path/gitlink/current/dirty state without fetching from the network.
- `update` — fetch and align root-owned direct dependencies, then restore/validate nested external dependencies at each consumed owner's committed gitlink; dirty dependencies are refused.

After `bootstrap` or `update`, review parent-repository changes with `git status`. Dependency updates intentionally appear as normal reviewable gitlink changes.

Generated root launchers also expose read-only full-closure status:

```bash
./update-repo.sh status
```

```powershell
.\update-repo.ps1 status
```

A consumed repository's committed nested gitlink remains its exact dependency pin. Its `project.yml ref` is validated as owner metadata; the outer consumer does not advance that nested gitlink independently.

## Optional Moon orchestration

Moon is an **opt-in companion**, not a prerequisite for the Git commands above. It exists to shorten build/release feedback by skipping unchanged high-level domain work and hydrating reusable outputs/evidence on fresh runners.

Local entrypoints:

```bash
./moon-project.sh bootstrap
./moon-project.sh validate --repo .
./moon-project.sh cache-paths --repo .
./moon-project.sh run consumer:java.canonical --repo .
```

PowerShell uses the equivalent `moon-project.ps1` commands.

For an explicit host-side affected preflight, checkout the exact head shallow and blobless, then fetch only the exact base commit shallowly. Submodules can remain uninitialised until the gate says domain work is needed:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7
  with:
    ref: ${{ env.HEAD_SHA }}
    fetch-depth: 1
    filter: blob:none
    submodules: false

- shell: bash
  run: git fetch --no-tags --depth=1 origin "$BASE_SHA"

- uses: brainboxemb/tool.git-project/moon/affected@v0.2.6
  with:
    task: consumer:scad.ci
    base: ${{ env.BASE_SHA }}
    head: ${{ env.HEAD_SHA }}
```

Moon 2.5.4 is qualified for this explicit two-revision comparison even when both commits are shallow history roots and intervening ancestry is not traversable. Workflows that need merge-base discovery or other ancestry traversal can still require fuller history; that is a different VCS contract.

For production/cache execution, use the Moon action after the affected gate:

```yaml
- uses: brainboxemb/tool.git-project/moon@v0.2.6
  with:
    task: consumer:java.canonical
    cache-namespace: java-canonical
```

The affected action treats an aggregate target as affected when Moon marks the target itself or work upstream of it affected, using Moon's own task graph rather than a duplicated changed-path/dependency model. Query uncertainty remains conservative and returns `affected=true`.

The production action caches the pinned Moon runtime separately from Moon's portable `hashes` / `outputs` task cache. Domain task outputs retain their original producer evidence; the current Moon invocation writes separate materialization evidence.

See [`docs/moon-orchestration.md`](docs/moon-orchestration.md) for the full production contract and ownership boundary.

## Persistent producer execution evidence

Persistent generated output may include a domain-neutral producer execution envelope at:

```text
evidence/executions/<execution-id>/
  execution.json
  execution.log
```

The normative machine-readable contract is [`schemas/execution-evidence.schema.json`](schemas/execution-evidence.schema.json). It records the producer capability, action owner, exact source/owner revisions, result, retained human-readable log and links to richer domain evidence without flattening Java, SCAD or documentation semantics.

Producer execution evidence is separate from current Moon materialization evidence under `orchestration/` and must not be rewritten when equivalent producer output is later hydrated.

See [`docs/execution-evidence.md`](docs/execution-evidence.md) for the ownership, schema and publication rules.

## Consumer bootstrap launchers

A consumer has a chicken-and-egg problem: `tool.git-project` must exist before it can run. The [`bootstrap/`](bootstrap/) directory therefore contains tiny root-launcher templates.

They require the bootstrap tool to be a **committed gitlink**, restore that exact pinned commit with `git submodule update --init`, and then delegate to the generic implementation. They do not follow `main` or invent a bootstrap version when the gitlink is missing.

The substantial dependency logic stays here rather than being copied into every consumer.

The root launchers are centrally managed copies with source/version/revision metadata. Normal bootstrap/update checks for drift and refreshes unpatched copies from the exact pinned tool revision. A deliberate consumer patch must be declared through the `Managed-Local-Patch` header and is then preserved. Domain tooling extends update through an optional `consumer/post-update.*` hook instead of replacing the generic root launcher.

See [Managed consumer launchers](docs/managed-consumer-launchers.md) for the provenance, refresh and local-patch contract.

## Generated output lifecycle

Generated repository output uses one shared lifecycle independent of Java, SCAD, or documentation semantics:

```text
pull request #N     -> dev/pr-N/<suffix>
main                -> prod/<suffix>
release tag vX.Y.Z  -> rel/vX.Y.Z/<suffix>
```

The domain producer prepares the complete output tree and chooses the suffix it owns, for example `bld`, `docs`, `build`, or `verification`. `tool.git-project` only owns the Git/repository materialization step.

Two released interfaces share the same publication implementation:

- `generated-output/publish` publishes an already prepared tree directly from the current host job and leaves the caller worktree untouched, so multiple output families can be published sequentially without an artifact/job handoff;
- `.github/workflows/reusable-generated-output-publish.yml` remains the artifact-based wrapper for intentionally separate producer/publication jobs and delegates to that same action.

Both interfaces preserve the same branch mapping, exact-source stale checks, same-repository PR restriction and force-push safety. Direct same-job callers own job-level serialization for a target family; the reusable wrapper retains its built-in concurrency group.

See [`docs/generated-output-publication.md`](docs/generated-output-publication.md) for the full contract.

## PR preview branch cleanup

Generated PR output uses the shared repository convention:

```text
dev/pr-<N>/<suffix>
```

Examples include:

```text
dev/pr-17/build
dev/pr-17/verification
dev/pr-8/bld
dev/pr-4/docs
```

The reusable workflow `.github/workflows/reusable-pr-preview-cleanup.yml` owns only the generic Git lifecycle operation. The calling domain tool or repository declares which suffixes it owns.

Example caller:

```yaml
name: Cleanup PR previews

on:
  pull_request:
    types: [closed]

permissions:
  contents: write

jobs:
  cleanup:
    uses: brainboxemb/tool.git-project/.github/workflows/reusable-pr-preview-cleanup.yml@v0.2.0
    with:
      pr_number: ${{ github.event.pull_request.number }}
      preview_suffixes: |
        build
        verification
      delete_source_branch: true
```

The cleanup workflow only constructs deletion targets under `dev/pr-<positive integer>/<validated suffix>`. Callers cannot use it to delete `prod/*`, release refs, the default branch, or an arbitrary branch name.

Deleting the merged source branch is optional and only applies to a same-repository merged pull request. A manual or non-PR invocation therefore cannot trigger source-branch deletion through that option.

## Ref policy

Preferred refs for dependencies managed through `project.yml` are:

1. immutable full commit SHA for maximum reproducibility;
2. stable version tag;
3. branch only when a deliberately moving development dependency is desired.

Branch refs are supported but are not immutable. A bootstrap/update resolves the branch to a concrete commit and records that commit through the parent repository gitlink.

The bootstrap engine itself is always pinned by its parent gitlink. Reusable GitHub workflows/actions use released tags; do not call them from moving `main`.

## Self-test fixture

`fixture/` is intentionally build-system-neutral. CI creates a temporary Git consumer repository, pins the current `tool.git-project` revision as its bootstrap gitlink, removes the initialized worktree to emulate a fresh clone, and then proves root-level bootstrap plus managed dependency validation, status and idempotent update on both Linux and Windows.

Separate lifecycle tests exercise PR-preview cleanup, generated-output publication, the reusable release contract, the execution-evidence schema/fixtures, and the optional Moon production interface. Moon's architectural behavior was qualified before production implementation; the owner regression here only proves the released wrapper preserves the accepted cache/hydration contract on Linux and Windows.
