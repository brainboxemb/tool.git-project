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
- `role` — generic purpose, normally `tooling` or `external`; other values are allowed because the Git layer does not own domain semantics;
- `type` — initial implementation supports only `git-submodule`;
- `url` — Git repository URL;
- `path` — repository-relative submodule path;
- `ref` — desired commit, tag, or branch.

Names and paths must be unique. Paths must be relative and may not escape the repository with `..`.

`tools/tool.git-project` itself must not be repeated in this list.

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
