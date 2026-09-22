# Managed consumer launchers

Root consumer launchers are managed repository interfaces, not independent
project code.

The two logical launcher families are:

- `bootstrap.ps1` / `bootstrap.sh`;
- `update-repo.ps1` / `update-repo.sh`.

Their canonical generic sources live under `bootstrap/` in
`tool.git-project`. Generated consumer copies retain the canonical source,
source version and exact source revision in their header. A consumer may keep a
deliberate local patch, but must declare it in the same header so automatic
refresh never silently erases it.

Domain tooling does not replace the root update launcher. A tooling dependency
may instead expose an optional platform-specific post-update hook which runs
after the generic dependency update.
