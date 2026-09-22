# Generic project configuration

Status: initial working contract

## Purpose

`project.yml` contains repository-level information that is independent from the build technology used by the project.

Build-system-specific configuration belongs in separate profile files.

The bootstrap engine itself (`tools/tool.git-project`) is not managed recursively through `project.yml`; it is pinned directly by the parent repository Git submodule/gitlink.

Example:

```yaml
schema_version: 1

project:
  name: 2026-010-02.java.event-timing-framework

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

## Bootstrap engine pin

A consumer repository should separately contain:

```text
.gitmodules
bootstrap.ps1
bootstrap.sh
update-repo.ps1
update-repo.sh
tools/tool.git-project    # mode 160000 Git gitlink
```

The gitlink records the exact bootstrap-engine commit. Root bootstrap launchers run `git submodule update --init -- tools/tool.git-project` and then delegate to that exact revision.

This special case avoids recursive self-management and ensures the tool required to parse `project.yml` is available before managed dependencies are processed.

Creating a new consumer is a one-time repository-authoring operation:

```text
git submodule add https://github.com/brainboxemb/tool.git-project.git tools/tool.git-project
checkout the desired tool commit/tag inside the submodule
commit .gitmodules + tools/tool.git-project + root launchers
```

Normal users cloning the consumer do not choose a bootstrap version; the committed gitlink already does so.

## Fields

### `schema_version`

Required. Initial value is integer `1`.

### `project.name`

Required non-empty project/repository name used for diagnostics.

### `profiles[]`

Optional list of build/domain-specific configuration files.

Each item contains:

- `type` — profile identifier such as `java` or `scad`;
- `config` — repository-relative path to the profile YAML file.

`tool.git-project` verifies that the file exists but does not parse its content.

### `dependencies[]`

Optional list of Git-managed dependencies **after the bootstrap engine is available**.

Each dependency contains:

- `name` — unique logical dependency name;
- `role` — generic purpose. Root dependencies of every role are managed directly. `external` additionally means the dependency participates in the controlled transitive Git closure when its owner is consumed; other roles are not recursively initialized;
- `type` — initial implementation supports only `git-submodule`;
- `url` — Git repository URL;
- `path` — repository-relative submodule path;
- `ref` — desired commit, tag, or branch.

Names and paths must be unique. Paths must be relative and may not escape the repository with `..`.

`tools/tool.git-project` itself must not be repeated in this list.

## Controlled transitive external closure

For a root repository, all declared dependencies keep the existing direct
bootstrap/update behaviour.

When a declared dependency is itself consumed as a dependency, only entries
with both:

```text
role: external
type: git-submodule
```

are followed transitively. Nested tooling/development gitlinks are left
uninitialized.

A consumed owner remains authoritative for its nested dependency state:

- the nested path must be a committed gitlink in that owner;
- the matching `.gitmodules` URL and `project.yml` metadata are validated;
- the nested worktree is initialized/restored at the owner's committed gitlink;
- a full-SHA or tag ref must resolve to that exact gitlink;
- a branch ref must resolve, while the committed gitlink remains the exact
  reproducible owner pin;
- dirty nested worktrees are refused;
- traversal detects repository cycles on the current ancestry but allows the
  same repository at independent sibling/owner paths.

`status` is read-only and reports nested external entries with owner, path,
configured ref, exact gitlink/current revision and dirty/uninitialized state.
It does not fetch moving refs.

A consumer does not remove undeclared local paths or rewrite a consumed owner's
gitlinks. Removing or advancing a nested dependency remains an explicit change
in the repository that owns it.

## Ref semantics

A full commit SHA is immutable and preferred when a consumer must reproduce an exact tooling revision.

A tag is resolved to its commit after fetching tags. Stable semantic-version tags are the preferred human-readable release mechanism once a tool publishes releases.

A branch is deliberately moving. `bootstrap`/`update` resolve the current remote branch head to a concrete commit and check out that commit detached; the parent repository gitlink therefore still records exactly what was used.

The bootstrap engine's ref semantics are simpler: its parent gitlink is always the authoritative exact commit.

## Parent repository changes

The tool does not commit or stage dependency changes automatically.

After changing a configured ref and running `update`, the normal expected result is a reviewable change such as:

```text
M project.yml
M tools/tool.java-project
```

The project owner decides whether to commit those changes.

Updating the bootstrap engine itself is also a normal explicit submodule/gitlink update reviewed in the parent repository; it is not performed by `update-repo` v1.

## Supported YAML subset

The bootstrap scripts intentionally avoid requiring an external YAML runtime. Version 1 therefore supports a conservative block-style subset:

- spaces for indentation;
- scalar `key: value` fields;
- top-level `project:`, `profiles:`, and `dependencies:` sections;
- list entries beginning with `- type:` for profiles and `- name:` for dependencies;
- optional single or double quotes around scalar values;
- comments on their own lines.

Flow maps, anchors, aliases, multiline scalars, inline comments, and arbitrary nested structures are not part of the generic v1 parser.

Profile-specific files are free to use richer YAML because they are parsed by their owning tool, not by `tool.git-project`.


### Optional tooling post-update hook

A root dependency with `role: tooling` may expose one platform-specific
post-update hook:

```text
consumer/post-update.ps1
consumer/post-update.sh
```

The generic updater invokes the matching hook only after a successful root
dependency update. The hook receives the consumer repository root and may
perform domain-owned synchronization that depends on the newly accepted tooling
state. It must not reimplement generic dependency update/status logic.

PowerShell contract:

```powershell
param([string] $RepoRoot)
```

POSIX contract:

```text
post-update.sh --repo <repository-root>
```

No hook is required. A tooling dependency without one remains a normal generic
dependency.
