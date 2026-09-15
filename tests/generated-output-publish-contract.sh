#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${GITHUB_WORKSPACE}/generated-output-publish.sh"
root="$(mktemp -d "${RUNNER_TEMP:-/tmp}/generated-output-contract.XXXXXX")"
trap 'rm -rf "$root"' EXIT
remote="$root/remote.git"
work="$root/work"
out="$root/out"
empty="$root/empty"
mkdir -p "$out" "$empty"
printf 'generated-output contract\n' > "$out/file.txt"

git init --bare -q "$remote"
git init -q "$work"
git -C "$work" config user.name generated-output-test
git -C "$work" config user.email generated-output-test@example.invalid
printf 'base\n' > "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -q -m base
git -C "$work" branch -M main
git -C "$work" remote add origin "$remote"
git -C "$work" push -q -u origin main
main_sha="$(git -C "$work" rev-parse HEAD)"

run_pub() {
  env \
    GITHUB_REPOSITORY=fixture/repository \
    GITHUB_SERVER_URL=https://github.com \
    PUBLISH_REMOTE_URL="$remote" \
    PUBLISH_TOKEN=fixture-token \
    PUBLISH_SOURCE_DIR="$out" \
    "$@" \
    "$SCRIPT"
}
assert_missing_branch() {
  if git --git-dir="$remote" show-ref --verify --quiet "refs/heads/$1"; then
    echo "unexpected branch exists: $1" >&2
    exit 1
  fi
}

run_pub GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main GITHUB_REF_NAME=main GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX=main-test
test "$(git --git-dir="$remote" show refs/heads/prod/main-test:file.txt)" = 'generated-output contract'

git -C "$work" switch -q -c feature/test
printf 'pr\n' >> "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -q -m pr
git -C "$work" push -q -u origin feature/test
pr_sha="$(git -C "$work" rev-parse HEAD)"
status_before="$(git -C "$work" status --porcelain)"
head_before="$(git -C "$work" rev-parse HEAD)"
for suffix in pr-first pr-second; do
  run_pub GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/7/merge GITHUB_REF_NAME=7/merge GITHUB_SHA=0000000000000000000000000000000000000000 PUBLISH_BRANCH_SUFFIX="$suffix" PUBLISH_PR_NUMBER=7 PUBLISH_PR_HEAD_REF=feature/test PUBLISH_PR_HEAD_SHA="$pr_sha" PUBLISH_PR_HEAD_REPOSITORY=fixture/repository
  test "$(git --git-dir="$remote" show "refs/heads/dev/pr-7/$suffix:file.txt")" = 'generated-output contract'
done
test "$(git -C "$work" status --porcelain)" = "$status_before"
test "$(git -C "$work" rev-parse HEAD)" = "$head_before"

git -C "$work" switch -q main
git -C "$work" tag -a v1.2.3 -m v1.2.3 "$main_sha"
git -C "$work" push -q origin v1.2.3
run_pub GITHUB_EVENT_NAME=push GITHUB_REF=refs/tags/v1.2.3 GITHUB_REF_NAME=v1.2.3 GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX=release-test
test "$(git --git-dir="$remote" show refs/heads/rel/v1.2.3/release-test:file.txt)" = 'generated-output contract'

run_pub GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main GITHUB_REF_NAME=main GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX=stale PUBLISH_SOURCE_REVISION=0000000000000000000000000000000000000000
assert_missing_branch prod/stale

if run_pub GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main GITHUB_REF_NAME=main GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX='bad/name'; then
  echo 'invalid suffix unexpectedly succeeded' >&2; exit 1
fi
if env GITHUB_REPOSITORY=fixture/repository GITHUB_SERVER_URL=https://github.com PUBLISH_REMOTE_URL="$remote" PUBLISH_TOKEN=fixture-token PUBLISH_SOURCE_DIR="$empty" GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main GITHUB_REF_NAME=main GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX=empty "$SCRIPT"; then
  echo 'empty publication unexpectedly succeeded' >&2; exit 1
fi
if run_pub GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/main GITHUB_REF_NAME=main GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX=bad-source PUBLISH_SOURCE_REVISION=abc; then
  echo 'invalid source revision unexpectedly succeeded' >&2; exit 1
fi
if run_pub GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/9/merge GITHUB_REF_NAME=9/merge GITHUB_SHA=0000000000000000000000000000000000000000 PUBLISH_BRANCH_SUFFIX=fork PUBLISH_PR_NUMBER=9 PUBLISH_PR_HEAD_REF=feature/test PUBLISH_PR_HEAD_SHA="$pr_sha" PUBLISH_PR_HEAD_REPOSITORY=other/repository; then
  echo 'fork publication unexpectedly succeeded' >&2; exit 1
fi
if run_pub GITHUB_EVENT_NAME=push GITHUB_REF=refs/heads/feature GITHUB_REF_NAME=feature GITHUB_SHA="$main_sha" PUBLISH_BRANCH_SUFFIX=unsupported; then
  echo 'unsupported source ref unexpectedly succeeded' >&2; exit 1
fi

git -C "$work" switch -q -c feature/race main
printf 'race1\n' >> "$work/README.md"
git -C "$work" add README.md
git -C "$work" commit -q -m race1
git -C "$work" push -q -u origin feature/race
race_sha="$(git -C "$work" rev-parse HEAD)"
(
  sleep 0.3
  printf 'race2\n' >> "$work/README.md"
  git -C "$work" add README.md
  git -C "$work" commit -q -m race2
  git -C "$work" push -q origin feature/race
) &
updater=$!
run_pub GITHUB_EVENT_NAME=pull_request GITHUB_REF=refs/pull/8/merge GITHUB_REF_NAME=8/merge GITHUB_SHA=0000000000000000000000000000000000000000 PUBLISH_BRANCH_SUFFIX=race PUBLISH_PR_NUMBER=8 PUBLISH_PR_HEAD_REF=feature/race PUBLISH_PR_HEAD_SHA="$race_sha" PUBLISH_PR_HEAD_REPOSITORY=fixture/repository PUBLISH_BEFORE_PUSH_DELAY_SECONDS=1
wait "$updater"
assert_missing_branch dev/pr-8/race

echo 'generated-output publisher contract: OK'
