# Generated output publication

`tool.git-project` owns the generic Git/repository operation that materializes an already prepared generated-output tree on a persistent generated branch.

The domain producer remains responsible for building the content. This workflow does not run Maven, SCons, OpenSCAD, document generators, tests, or other domain engines.

## Branch lifecycle

The caller supplies one validated suffix, such as `bld`, `docs`, `build`, or `verification`. The target branch is derived from trusted GitHub event context:

```text
pull request #N     -> dev/pr-N/<suffix>
main                -> prod/<suffix>
release tag vX.Y.Z  -> rel/vX.Y.Z/<suffix>
```

Arbitrary target branch names are not accepted as inputs.

## Workflow

Call the released reusable workflow:

```yaml
jobs:
  publish:
    permissions:
      contents: write
    uses: brainboxemb/tool.git-project/.github/workflows/reusable-generated-output-publish.yml@v0.1.1
    with:
      artifact_name: prepared-output
      branch_suffix: bld
```

The Actions artifact must already contain the complete tree that should become the generated branch contents. Publication does not modify producer evidence or infer a producer revision.

## Ownership boundary

`tool.git-project` owns:

- validation of the branch suffix;
- mapping GitHub event context to the generated branch namespace;
- safe branch materialization and force replacement;
- repository credentials needed for the Git push.

The caller/domain owner owns:

- how output is generated;
- which files belong in the prepared artifact;
- evidence semantics and provenance content;
- the suffix representing its output family;
- when publication should run relative to domain verification/release steps.

## Safety

Publication is accepted only for:

- same-repository pull requests;
- `refs/heads/main`;
- strict release tags matching `vX.Y.Z`.

Suffixes are restricted to a single safe branch component. Unsupported refs fail rather than silently publishing elsewhere.

PR preview removal remains a separate generic lifecycle operation provided by `reusable-pr-preview-cleanup.yml`.
