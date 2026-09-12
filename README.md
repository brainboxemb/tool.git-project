# tool.git-project

Reusable Git project tooling for dependency bootstrap, pinned external repositories, submodule management, and controlled updates.

`tool.git-project` owns the repository-level dependency mechanism shared by Java, SCAD, and future engineering projects. It deliberately does **not** own Java/Maven, OpenSCAD/SCons, documentation-rendering, Docker, or product-domain behaviour.

## Model

A consumer keeps generic repository/dependency information in `project.yml` and keeps build-system-specific settings in profile files such as `project.java.yml` or `project.scad.yml`.

```text
project.yml
  project metadata
  profiles -> project.<profile>.yml
  dependencies[]
       |
       v
tool.git-project
  validate / bootstrap / status / update
       |
       +--> Git submodules / pinned refs

project.java.yml  -> tool.java-project
project.scad.yml  -> tool.scad-project
```

The Git tool validates that configured profile files exist, but treats their contents as opaque.

## Generic dependency example

```yaml
schema_version: 1

project:
  name: my-project

profiles:
  - type: java
    config: project.java.yml

dependencies:
  - name: tool.git-project
    role: tooling
    type: git-submodule
    url: https://github.com/brainboxemb/tool.git-project.git
    path: tools/tool.git-project
    ref: <pinned-tag-or-commit>

  - name: tool.java-project
    role: tooling
    type: git-submodule
    url: https://github.com/brainboxemb/tool.java-project.git
    path: tools/tool.java-project
    ref: 5a7135194b94644129d05a5f4a8ceffc5de499bf
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

The commands can also operate on another local repository, which is useful for CI and tooling tests:

```powershell
.\git-project.ps1 bootstrap -RepoRoot C:\work\consumer
```

```bash
./git-project.sh bootstrap --repo /work/consumer
```

### Command semantics

- `validate` — parse and validate generic `project.yml`; verify referenced profile files exist.
- `bootstrap` — register/repair declared submodules where possible, initialise them, and align them to configured refs.
- `status` — inspect local registration, current commit, configured ref, and dirty state without fetching from the network.
- `update` — fetch dependencies and align their gitlinks to the refs currently requested by `project.yml`; dirty dependencies are refused.

After `bootstrap` or `update`, review parent-repository changes with `git status`. Dependency updates intentionally appear as normal reviewable gitlink changes.

## Consumer bootstrap launchers

A consumer has a chicken-and-egg problem: `tool.git-project` must exist before it can run. The [`bootstrap/`](bootstrap/) directory therefore contains tiny root-launcher templates. They only make `tools/tool.git-project` available and then delegate to the generic implementation.

The substantial dependency logic stays here rather than being copied into every consumer.

## Ref policy

Preferred refs are:

1. immutable full commit SHA for maximum reproducibility;
2. stable version tag;
3. branch only when a deliberately moving development dependency is desired.

Branch refs are supported but are not immutable. A bootstrap/update resolves the branch to a concrete commit and records that commit through the parent repository gitlink.

## Self-test fixture

`fixture/` is intentionally build-system-neutral. CI creates a temporary Git repository from the fixture, then proves validation, bootstrap, local status, controlled update, and deterministic checkout of a real public dependency on both Linux and Windows.
