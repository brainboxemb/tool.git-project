# Generic release lifecycle

`tool.git-project` owns repository-level release mechanics that are independent of Java, SCAD, documentation generation, or another build domain.

The reusable workflow is:

```text
.github/workflows/reusable-release.yml
```

It can:

- parse `release-request/vX.Y.Z/<sha>` branches or explicit dispatch inputs;
- validate `vX.Y.Z`, an exact source SHA, `VERSION`, and `CHANGELOG.md`;
- require successful named workflows on the exact production commit;
- create an annotated release tag;
- dispatch an optional verification workflow on that tag and optionally wait for success;
- optionally create a plain GitHub Release from the matching changelog section;
- remove the temporary release-request branch.

It does **not** define domain-specific build, test, provenance, or release-asset semantics.

## Thin consumer caller

A domain tool keeps the trigger and declares its gates. For example:

```yaml
name: Release example tool

on:
  workflow_dispatch:
    inputs:
      version:
        required: true
        type: string
      release_sha:
        required: true
        type: string
  push:
    branches:
      - 'release-request/**'

permissions:
  contents: write
  actions: write

jobs:
  release:
    # Generic request validation and tag creation belong to tool.git-project.
    # Domain-specific tagged verification/provenance remains in this repository.
    uses: brainboxemb/tool.git-project/.github/workflows/reusable-release.yml@v0.1.2
    with:
      version: ${{ inputs.version || '' }}
      release_sha: ${{ inputs.release_sha || '' }}
      required_main_workflows: |
        self-test.yml
      tagged_verification_workflow: self-test.yml
```

Reusable workflows must be consumed from a deliberate released tag or immutable commit, not moving `main`.

## Domain-specific release finalization

A caller may leave `create_github_release: false` and let its tagged verification workflow create the GitHub Release after domain-specific evidence has been produced. This is the preferred pattern when the Release contains domain-owned provenance or assets.

For a repository with no domain-specific release assets, `create_github_release: true` lets the generic workflow create a plain Release from the matching `CHANGELOG.md` section. Set `wait_for_tagged_verification: true` when release creation must wait for a dispatched tagged verification workflow.

## Dry-run validation

`dry_run: true` validates release metadata without creating a tag, dispatching verification, creating a Release, or deleting refs. `tool.git-project` uses this mode from its PR test so the reusable contract is exercised before a release is attempted.
