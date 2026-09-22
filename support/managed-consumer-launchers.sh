#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-check}"
if [[ $# -gt 0 ]]; then shift; fi
repo_root=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) repo_root="${2:-}"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$command_name" in
  check|refresh) ;;
  *) echo "Usage: $0 {check|refresh} [--repo PATH]" >&2; exit 2 ;;
esac

command -v git >/dev/null 2>&1 || { echo "Git was not found in PATH." >&2; exit 1; }

tool_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool_version="$(tr -d '\r\n' < "$tool_root/VERSION")"
tool_revision="$(git -C "$tool_root" rev-parse HEAD)"
if [[ -n "$repo_root" ]]; then
  repo_root="$(git -C "$repo_root" rev-parse --show-toplevel)"
else
  repo_root="$(git rev-parse --show-toplevel)"
fi

sources=("bootstrap/consumer-bootstrap.ps1" "bootstrap/consumer-bootstrap.sh" "bootstrap/consumer-update.ps1" "bootstrap/consumer-update.sh")
targets=("bootstrap.ps1" "bootstrap.sh" "update.ps1" "update.sh")

render_launcher() {
  local source="$1"
  sed -e "s/@TOOL_GIT_PROJECT_VERSION@/$tool_version/g" -e "s/@TOOL_GIT_PROJECT_REVISION@/$tool_revision/g" "$tool_root/$source"
}

for i in "${!sources[@]}"; do
  source="${sources[$i]}"
  target="${targets[$i]}"
  target_file="$repo_root/$target"
  tmp="$(mktemp)"
  render_launcher "$source" > "$tmp"

  if [[ -f "$target_file" ]] && cmp -s "$target_file" "$tmp"; then
    rm -f "$tmp"
    continue
  fi

  patch=""
  if [[ -f "$target_file" ]]; then
    patch="$(sed -n -E 's/^# Managed-Local-Patch:[[:space:]]*(.+)[[:space:]]*$/\1/p' "$target_file" | head -n1)"
  fi

  if [[ -n "$patch" && "$patch" != "none" ]]; then
    echo "WARNING: Managed launcher '$target' has declared local patch '$patch'; preserving it. Canonical source: brainboxemb/tool.git-project/$source@$tool_version ($tool_revision)." >&2
    rm -f "$tmp"
    continue
  fi

  if [[ "$command_name" == "check" ]]; then
    echo "WARNING: Managed launcher drift: '$target' differs from brainboxemb/tool.git-project/$source@$tool_version ($tool_revision)." >&2
    rm -f "$tmp"
    continue
  fi

  cat "$tmp" > "$target_file"
  [[ "$target" == *.sh ]] && chmod +x "$target_file"
  rm -f "$tmp"
  echo "Refreshed managed launcher: $target <- brainboxemb/tool.git-project/$source@$tool_version (${tool_revision:0:12})"
done
