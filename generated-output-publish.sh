#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

write_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
}

source_dir="${PUBLISH_SOURCE_DIR:-}"
branch_suffix="${PUBLISH_BRANCH_SUFFIX:-}"
source_revision_input="${PUBLISH_SOURCE_REVISION:-}"
token="${PUBLISH_TOKEN:-}"
pr_number="${PUBLISH_PR_NUMBER:-}"
pr_head_ref="${PUBLISH_PR_HEAD_REF:-}"
pr_head_sha="${PUBLISH_PR_HEAD_SHA:-}"
pr_head_repository="${PUBLISH_PR_HEAD_REPOSITORY:-}"
repository="${GITHUB_REPOSITORY:-}"
server_url="${GITHUB_SERVER_URL:-https://github.com}"
remote_url="${PUBLISH_REMOTE_URL:-}"

[[ -n "$source_dir" ]] || fail "PUBLISH_SOURCE_DIR is required"
[[ -d "$source_dir" ]] || fail "prepared generated-output directory does not exist: $source_dir"
if [[ -d "$source_dir/.git" || -f "$source_dir/.git" ]]; then
  fail "prepared generated-output directory must not contain .git metadata"
fi
if ! find "$source_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  fail "prepared generated-output directory is empty: $source_dir"
fi

[[ "$branch_suffix" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid generated-output branch suffix: $branch_suffix"
[[ -n "$repository" ]] || fail "GITHUB_REPOSITORY is required"
[[ -n "$token" ]] || fail "publication token is required"

if [[ -z "$remote_url" ]]; then
  remote_url="${server_url%/}/${repository}.git"
fi

credential_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/generated-output-credentials.XXXXXX")"
publish_repo="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/generated-output-publish.XXXXXX")"
cleanup() {
  rm -f "$credential_file"
  rm -rf "$publish_repo"
}
trap cleanup EXIT
chmod 600 "$credential_file"

server_host="${server_url#*://}"
server_host="${server_host%%/*}"
printf 'https://x-access-token:%s@%s\n' "$token" "$server_host" > "$credential_file"

git_with_credentials() {
  git -c credential.helper="store --file=$credential_file" "$@"
}

ls_remote_ref() {
  local ref="$1"
  git_with_credentials ls-remote "$remote_url" "$ref" | awk 'NR == 1 { print $1 }'
}

resolve_tag_commit() {
  local tag="$1"
  local lines peeled direct
  lines="$(git_with_credentials ls-remote "$remote_url" "refs/tags/${tag}" "refs/tags/${tag}^{}")"
  peeled="$(printf '%s\n' "$lines" | awk '$2 ~ /\^\{\}$/ { print $1; exit }')"
  direct="$(printf '%s\n' "$lines" | awk '$2 !~ /\^\{\}$/ { print $1; exit }')"
  printf '%s\n' "${peeled:-$direct}"
}

publication_context=""
target_branch=""
current_source_revision() {
  local revision=""
  case "${GITHUB_EVENT_NAME:-}" in
    pull_request)
      [[ "$pr_head_repository" == "$repository" ]] || fail "generated-output publication is only allowed for same-repository pull requests"
      [[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || fail "missing or invalid pull-request number"
      [[ -n "$pr_head_ref" ]] || fail "missing pull-request head ref"
      git check-ref-format "refs/heads/$pr_head_ref" >/dev/null 2>&1 || fail "invalid pull-request head ref: $pr_head_ref"
      revision="$(ls_remote_ref "refs/heads/$pr_head_ref")"
      ;;
    push|workflow_dispatch)
      if [[ "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
        revision="$(ls_remote_ref 'refs/heads/main')"
      elif [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
        [[ "${GITHUB_REF_NAME:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release tag must match vX.Y.Z: ${GITHUB_REF_NAME:-}"
        revision="$(resolve_tag_commit "$GITHUB_REF_NAME")"
      else
        fail "generated-output publication is only allowed for same-repository pull requests, main, or vX.Y.Z release tags; got ${GITHUB_REF:-<unset>}"
      fi
      ;;
    *)
      if [[ "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
        revision="$(ls_remote_ref 'refs/heads/main')"
      elif [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
        [[ "${GITHUB_REF_NAME:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release tag must match vX.Y.Z: ${GITHUB_REF_NAME:-}"
        revision="$(resolve_tag_commit "$GITHUB_REF_NAME")"
      else
        fail "unsupported generated-output publication event/ref: ${GITHUB_EVENT_NAME:-<unset>} ${GITHUB_REF:-<unset>}"
      fi
      ;;
  esac
  printf '%s\n' "$revision"
}

case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    [[ "$pr_head_repository" == "$repository" ]] || fail "generated-output publication is only allowed for same-repository pull requests"
    [[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || fail "missing or invalid pull-request number"
    [[ -n "$pr_head_ref" ]] || fail "missing pull-request head ref"
    target_branch="dev/pr-${pr_number}/${branch_suffix}"
    publication_context="pull request #${pr_number}"
    ;;
  *)
    if [[ "${GITHUB_REF:-}" == "refs/heads/main" ]]; then
      target_branch="prod/${branch_suffix}"
      publication_context="main"
    elif [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
      [[ "${GITHUB_REF_NAME:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release tag must match vX.Y.Z: ${GITHUB_REF_NAME}"
      target_branch="rel/${GITHUB_REF_NAME}/${branch_suffix}"
      publication_context="release tag ${GITHUB_REF_NAME}"
    else
      fail "generated-output publication is only allowed for same-repository pull requests, main, or vX.Y.Z release tags; got ${GITHUB_REF:-<unset>}"
    fi
    ;;
esac

current_revision="$(current_source_revision)"
[[ "$current_revision" =~ ^[0-9a-f]{40}$ ]] || fail "could not resolve current source revision for ${publication_context}"

source_revision="$source_revision_input"
if [[ -z "$source_revision" ]]; then
  if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
    source_revision="$pr_head_sha"
  elif [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
    source_revision="$current_revision"
  else
    source_revision="${GITHUB_SHA:-}"
  fi
fi
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || fail "source revision must be an exact 40-character commit SHA"

write_output target_branch "$target_branch"
write_output source_revision "$source_revision"

if [[ "$source_revision" != "$current_revision" ]]; then
  echo "Skipping stale generated-output publication for ${publication_context}: run source ${source_revision}, current source ${current_revision}."
  write_output published false
  write_output reason stale-before-staging
  exit 0
fi

git -C "$publish_repo" init -q
git -C "$publish_repo" config user.name "github-actions[bot]"
git -C "$publish_repo" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$publish_repo" config credential.helper "store --file=$credential_file"
git -C "$publish_repo" remote add origin "$remote_url"
git -C "$publish_repo" switch --orphan generated-output-publication >/dev/null
cp -a "$source_dir/." "$publish_repo/"
git -C "$publish_repo" add -A
if git -C "$publish_repo" diff --cached --quiet; then
  fail "prepared generated-output tree produced no publishable files"
fi
git -C "$publish_repo" commit -q -m "Publish generated output to ${target_branch}"

if [[ "${PUBLISH_BEFORE_PUSH_DELAY_SECONDS:-0}" != "0" ]]; then
  sleep "$PUBLISH_BEFORE_PUSH_DELAY_SECONDS"
fi

latest_revision="$(current_source_revision)"
[[ "$latest_revision" =~ ^[0-9a-f]{40}$ ]] || fail "could not resolve latest source revision for ${publication_context}"
if [[ "$source_revision" != "$latest_revision" ]]; then
  echo "Skipping stale generated-output publication for ${publication_context}: source advanced to ${latest_revision} before push."
  write_output published false
  write_output reason stale-before-push
  exit 0
fi

git_with_credentials -C "$publish_repo" push --force origin "HEAD:refs/heads/${target_branch}"

echo "Published generated output from ${source_revision} to ${target_branch}"
write_output published true
write_output reason published
