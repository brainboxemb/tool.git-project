# Generated output publication

`tool.git-project` owns the generic Git/repository operation that materializes an already prepared generated-output tree on a persistent generated branch.

The domain producer remains responsible for building the content. Publication does not run Maven, SCons, OpenSCAD, document generators, tests, or other domain engines.

## Branch lifecycle

The caller supplies one validated suffix, such as `bld`, `docs`, `build`, or `verification`. The target branch is derived from trusted GitHub event context:

```text
pull request #N     -> dev/pr-N/<suffix>
main                -> prod/<suffix>
release tag vX.Y.Z  -> rel/vX.Y.Z/<suffix>
```

Arbitrary target branch names are not accepted as inputs.

## Same-job action

When generated output already exists on the current host runner, use the released composite action directly. This avoids an artifact upload/download and an additional GitHub job boundary:

```yaml
permissions:
  contents: write

steps:
  - name: Publish Build output
    uses: brainboxemb/tool.git-project/generated-output/publish@v0.2.7
    with:
      source-directory: ${{ runner.temp }}/build-publication
      branch-suffix: build
      token: ${{ github.token }}

  - name: Publish Verification output
    uses: brainboxemb/tool.git-project/generated-output/publish@v0.2.7
    with:
      source-directory: ${{ runner.temp }}/verification-publication
      branch-suffix: verification
      token: ${{ github.token }}
```

The publisher stages and commits each tree in its own temporary Git repository. It does not switch branches, clean, stage, or commit inside the caller worktree. Multiple output families can therefore be published sequentially in one job.

Normally the action infers the source revision from the triggering pull-request head, `main` commit, or release tag. An optional exact `source-revision` can be supplied by a controlling orchestrator; it is still checked against the current remote source before staging and immediately before the force-push.

Direct same-job callers own their GitHub job-level concurrency. Do not intentionally run parallel writers for the same repository/source-context/suffix. Source-freshness checks still prevent an older source revision from overwriting output after the source has advanced.

## Artifact-based reusable workflow

Existing consumers can continue using the reusable workflow when production and publication are intentionally separate jobs:

```yaml
jobs:
  publish:
    permissions:
      contents: write
    uses: brainboxemb/tool.git-project/.github/workflows/reusable-generated-output-publish.yml@v0.2.7
    with:
      artifact_name: prepared-output
      branch_suffix: bld
```

The Actions artifact must already contain the complete tree that should become the generated branch contents. The reusable workflow checks out its own exact released publisher implementation, downloads the artifact, and delegates the branch operation to the same composite action used by same-job callers.

Its existing concurrency group serializes publication to the same repository/source-context/suffix. The wrapper remains useful when a producer job deliberately hands prepared output to a separate publication job.

## Ownership boundary

`tool.git-project` owns:

- validation of the branch suffix;
- mapping GitHub event context to the generated branch namespace;
- same-repository pull-request enforcement;
- exact source-revision validation;
- source-freshness checks before staging and immediately before force-push;
- temporary isolated Git staging/commit mechanics;
- safe force replacement of only the selected generated branch;
- short-lived repository credentials used for Git reads and the push;
- artifact-wrapper concurrency when the reusable workflow is used.

The caller/domain owner owns:

- how output is generated;
- which files belong in each prepared output tree;
- evidence semantics and provenance content;
- the suffix representing its output family;
- when publication should run relative to domain verification/release steps;
- job-level serialization when using the direct same-job action.

## Safety

Publication is accepted only for:

- same-repository pull requests;
- `refs/heads/main`;
- strict release tags matching `vX.Y.Z`.

Suffixes are restricted to a single safe branch component. The prepared tree must be non-empty and must not contain `.git` metadata. Unsupported refs, invalid source revisions, unsafe suffixes and empty trees fail rather than silently publishing elsewhere.

For pull requests and `main`, the publisher checks that the run's exact source revision is still current before staging and again immediately before the destructive force-push. If the source has advanced, the stale invocation exits successfully without changing the generated branch.

Release-tag publication resolves the tag's exact commit, including annotated tags, and therefore does not follow a moving branch head.

PR preview removal remains a separate generic lifecycle operation provided by `reusable-pr-preview-cleanup.yml`.
