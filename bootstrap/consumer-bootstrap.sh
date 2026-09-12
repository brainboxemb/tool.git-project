#!/usr/bin/env bash
set -euo pipefail

tool_path="tools/tool.git-project"
tool_url="https://github.com/brainboxemb/tool.git-project.git"
command -v git >/dev/null 2>&1 || { echo "Git was not found in PATH." >&2; exit 1; }
root="$(git rev-parse --show-toplevel)"
entry="$(git -C "$root" ls-files --stage -- "$tool_path" 2>/dev/null || true)"
if [[ ! "$entry" =~ ^160000[[:space:]] ]]; then
  echo "Registering bootstrap dependency: $tool_path"
  git -C "$root" submodule add --force "$tool_url" "$tool_path"
fi
git -C "$root" submodule sync -- "$tool_path" >/dev/null
git -C "$root" submodule update --init -- "$tool_path" >/dev/null
"$root/$tool_path/git-project.sh" bootstrap --repo "$root"
