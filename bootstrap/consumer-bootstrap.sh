#!/usr/bin/env bash
# Managed-Source: brainboxemb/tool.git-project/bootstrap/consumer-bootstrap.sh
# Managed-Source-Version: @TOOL_GIT_PROJECT_VERSION@
# Managed-Source-Revision: @TOOL_GIT_PROJECT_REVISION@
# Managed-Local-Patch: none
set -euo pipefail

tool_path="tools/tool.git-project"
command -v git >/dev/null 2>&1 || { echo "Git was not found in PATH." >&2; exit 1; }
root="$(git rev-parse --show-toplevel)"
entry="$(git -C "$root" ls-files --stage -- "$tool_path" 2>/dev/null || true)"
if [[ ! "$entry" =~ ^160000[[:space:]]+([0-9a-fA-F]{40})[[:space:]] ]]; then
  echo "Bootstrap dependency '$tool_path' is not a committed gitlink." >&2
  echo "Register tool.git-project once with 'git submodule add https://github.com/brainboxemb/tool.git-project.git $tool_path', pin the desired commit, and commit .gitmodules + the gitlink." >&2
  exit 1
fi
expected="${BASH_REMATCH[1],,}"
tool_root="$root/$tool_path"
current=""
if [[ -d "$tool_root" ]] && git -C "$tool_root" rev-parse --show-toplevel >/dev/null 2>&1; then
  current="$(git -C "$tool_root" rev-parse HEAD)"
  if [[ -n "$(git -C "$tool_root" status --porcelain)" ]]; then
    echo "Bootstrap engine 'tool.git-project' has local changes; refusing to align it to the committed gitlink." >&2
    exit 1
  fi
fi

git -C "$root" submodule sync -- "$tool_path" >/dev/null
if [[ -n "$current" && "$current" != "$expected" ]]; then
  echo "Aligning bootstrap tool.git-project: $current -> $expected (committed gitlink)"
fi
git -C "$root" submodule update --init -- "$tool_path" >/dev/null
actual="$(git -C "$tool_root" rev-parse HEAD)"
[[ "$actual" == "$expected" ]] || {
  echo "Bootstrap engine did not align to committed gitlink $expected." >&2
  exit 1
}
"$tool_root/git-project.sh" bootstrap --repo "$root"
