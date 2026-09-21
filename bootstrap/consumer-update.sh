#!/usr/bin/env bash
set -euo pipefail
mode="${1:-update}"
tool_path="tools/tool.git-project"
root="$(git rev-parse --show-toplevel)"
tool="$root/$tool_path/git-project.sh"
[[ -x "$tool" ]] || { echo "tool.git-project is not initialized. Run ./bootstrap.sh first." >&2; exit 1; }
case "$mode" in
  update|status) "$tool" "$mode" --repo "$root" ;;
  *) echo "Usage: ./update-repo.sh [update|status]" >&2; exit 2 ;;
esac
