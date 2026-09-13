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
    uses: brainboxemb/tool.git-project/.github/workflows/reusable-generated-output-publish.yml@v0.1.3
    with:
      artifact_name: prepared-output
      branch_suffix: bld
```

The Actions artifact must already contain the complete tree that should become the generated branch contents. Publication does not modify producer evidence or infer producer-specific provenance semantics.

Normally the publisher infers the source revision from the triggering pull-request head, `main` commit, or release tag. An explicit exact `source_revision` override exists for controlled orchestration/testing, but it is still checked against the current source before publication.

## Ownership boundary

`tool.git-project` owns:

- validation of the branch suffix;
- mapping GitHub event context to the generated branch namespace;
- source-freshness checks that prevent stale workflow runs overwriting newer PR or `main` output;
- concurrency for publication to the same repository/source-context/suffix;
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

For pull requests and `main`, the workflow checks that the run's source revision is still current before staging and again immediately before the force-push. If the source has advanced, the stale run exits successfully without changing the generated branch. A concurrency group additionally prevents publication jobs for the same target family from running concurrently.

Release-tag publication uses the immutable tag commit checked out by Actions and therefore does not follow a moving branch head.

PR preview removal remains a separate generic lifecycle operation provided by `reusable-pr-preview-cleanup.yml`.
