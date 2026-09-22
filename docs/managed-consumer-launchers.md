# Managed consumer launchers

Root consumer launchers are managed repository interfaces, not independent
project code.

The two logical launcher families are:

- `bootstrap.ps1` / `bootstrap.sh`;
- `update.ps1` / `update.sh`.

Their canonical generic sources live under `bootstrap/` in
`tool.git-project`. Generated consumer copies retain the canonical source,
source version and exact source revision in their header. A consumer may keep a
deliberate local patch, but must declare it in the same header so automatic
refresh never silently erases it.

Domain tooling does not replace the root update launcher. A tooling dependency
may instead expose an optional platform-specific post-update hook which runs
after the generic dependency update.


## Consumer metadata

Generated launchers contain:

```text
Managed-Source
Managed-Source-Version
Managed-Source-Revision
Managed-Local-Patch
```

`Managed-Source` names the canonical repository/path. Version and revision are
stamped from the exact `tool.git-project` checkout performing the refresh.

`Managed-Local-Patch: none` means the file is safe to refresh from the
canonical source. A deliberate consumer-specific edit must replace `none` with
a short issue/reason identifier before the file is changed. Refresh then
preserves that file and emits a warning instead of silently removing the patch.

Unmarked/legacy launcher differences are treated as drift: check emits a warning
and explicit/normal refresh adopts the canonical generic launcher.
