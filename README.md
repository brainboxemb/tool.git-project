# tool.git-project

Reusable Git project tooling for dependency bootstrap, pinned external repositories, submodule management, controlled updates, and generic repository Git lifecycle helpers.

`tool.git-project` owns the repository-level dependency mechanism shared by Java, SCAD, documentation, and future engineering projects. It deliberately does **not** own Java/Maven, OpenSCAD/SCons, documentation-rendering, Docker, or product-domain behaviour.

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
  validate / bootstrap / status / update
  generic Git lifecycle workflows
       |
       +--> managed Git submodules / pinned refs

project.java.yml  -> tool.java-project
project.scad.yml  -> tool.scad-project
```

The Git tool validates that configured profile files exist, but treats their contents as opaque.

## Tool release baseline

`VERSION` is the source-controlled release version of `tool.git-project`. Reusable GitHub workflows are released together with the normal Git tooling and are consumed through an immutable release tag such as `v0.1.1`, never through moving `main`.

For maximum reproducibility a consumer may additionally record or pin the exact commit behind the release tag in its committed gitlink/provenance. A normal release is created only from the exact current `main` commit after the required self-tests are green.

## Bootstrap dependency

`tool.git-project` is intentionally **not listed as a dependency in its own `project.yml` model**. It is the bootstrap engine required before that model can be processed.

A consumer pins it directly through the committed Git submodule/gitlink at:

```text
tools/tool.git-project
```

That gives a normal clean clone an exact bootstrap-tool commit without recursive self-management. The root `bootstrap.ps1` / `bootstrap.sh` launchers restore that committed gitlink and then delegate to the pinned tool.

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
    ref: dc94cf120ea4a196c9fc3daff4d22984ea4481c1
```

See [`docs/project-format.md`](docs/project-format.md) for the contract.

## Local commands

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
- `bootstrap` — register/repair declared managed submodules, initialise them, and align them to configured refs.
- `status` — inspect local registration, current commit, configured ref, and dirty state without fetching from the network.
- `update` — fetch managed dependencies and align their gitlinks to the refs currently requested by `project.yml`; dirty dependencies are refused.

After `bootstrap` or `update`, review parent-repository changes with `git status`. Dependency updates intentionally appear as normal reviewable gitlink changes.

## Consumer bootstrap launchers

A consumer has a chicken-and-egg problem: `tool.git-project` must exist before it can run. The [`bootstrap/`](bootstrap/) directory therefore contains tiny root-launcher templates.

They require the bootstrap tool to be a **committed gitlink**, restore that exact pinned commit with `git submodule update --init`, and then delegate to the generic implementation. They do not follow `main` or invent a bootstrap version when the gitlink is missing.

The substantial dependency logic stays here rather than being copied into every consumer.

## Generated output lifecycle

Generated repository output uses one shared lifecycle independent of Java, SCAD, or documentation semantics:

```text
pull request #N     -> dev/pr-N/<suffix>
main                -> prod/<suffix>
release tag vX.Y.Z  -> rel/vX.Y.Z/<suffix>
```

The domain producer prepares the complete output tree and chooses the suffix it owns, for example `bld`, `docs`, `build`, or `verification`. `tool.git-project` only owns the Git/repository materialization step.

The reusable workflow `.github/workflows/reusable-generated-output-publish.yml` accepts the prepared Actions artifact and a single validated suffix. It does not run domain build/test engines and it does not rewrite provenance.

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
    uses: brainboxemb/tool.git-project/.github/workflows/reusable-pr-preview-cleanup.yml@v0.1.1
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

The bootstrap engine itself is always pinned by its parent gitlink. Reusable GitHub workflows use released tags; do not call them from moving `main`.

## Self-test fixture

`fixture/` is intentionally build-system-neutral. CI creates a temporary Git consumer repository, pins the current `tool.git-project` revision as its bootstrap gitlink, removes the initialized worktree to emulate a fresh clone, and then proves root-level bootstrap plus managed dependency validation, status and idempotent update on both Linux and Windows.

Separate lifecycle tests exercise PR-preview cleanup and generated-output publication. The publication test runs in PR, `main`, and release-tag contexts, verifies the generated branch content, and removes its disposable test branch after validation.
