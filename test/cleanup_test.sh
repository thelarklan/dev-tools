#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=bashrc.d/git.sh
source "$project_dir/bashrc.d/git.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

real_git=$(command -v git)
fake_bin="$test_dir/bin"
fake_git_log="$test_dir/git.log"
fake_gh_log="$test_dir/gh.log"
upstream_work="$test_dir/upstream-work"
upstream_repo="$test_dir/upstream.git"
fork_repo="$test_dir/fork.git"
clone_dir="$test_dir/clone"

git init -b main "$upstream_work" >/dev/null
git -C "$upstream_work" config user.name Test
git -C "$upstream_work" config user.email test@example.com
printf 'base\n' >"$upstream_work/tracked.txt"
git -C "$upstream_work" add tracked.txt
git -C "$upstream_work" commit -m base >/dev/null
git clone --bare "$upstream_work" "$upstream_repo" >/dev/null 2>&1
git clone --bare "$upstream_work" "$fork_repo" >/dev/null 2>&1
git clone "$fork_repo" "$clone_dir" >/dev/null 2>&1
git -C "$clone_dir" config user.name Test
git -C "$clone_dir" config user.email test@example.com
git -C "$clone_dir" remote add upstream "$upstream_repo"
git -C "$clone_dir" fetch upstream main >/dev/null 2>&1
git -C "$clone_dir" symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/main
git -C "$clone_dir" remote set-url origin https://github.com/thelarkbot/project.git
git -C "$clone_dir" remote set-url --push origin "$fork_repo"
git -C "$clone_dir" remote set-url upstream git@github.com:upstream/project.git

git -C "$clone_dir" switch -c feature/cleanup >/dev/null
printf 'feature\n' >"$clone_dir/feature.txt"
git -C "$clone_dir" add feature.txt
git -C "$clone_dir" commit -m 'feature work' >/dev/null
git -C "$clone_dir" push --set-upstream origin feature/cleanup >/dev/null 2>&1
feature_commit=$($real_git -C "$clone_dir" rev-parse HEAD)

printf 'feature\n' >"$upstream_work/feature.txt"
git -C "$upstream_work" add feature.txt
git -C "$upstream_work" commit -m 'squash merged feature' >/dev/null
git -C "$upstream_work" push "$upstream_repo" main >/dev/null 2>&1
merge_commit=$($real_git -C "$upstream_work" rev-parse HEAD)

mkdir -p "$fake_bin"
cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GIT_LOG"
if [[ "${1:-}" == fetch && "${2:-}" == upstream && $# -eq 3 ]]; then
    exec "$REAL_GIT" fetch "$UPSTREAM_REPO" "$3:refs/remotes/upstream/$3"
fi
if [[ "${1:-} ${2:-} ${3:-} ${4:-}" == "ls-remote --exit-code --heads origin" ]]; then
    exec "$REAL_GIT" ls-remote --exit-code --heads "$FORK_REPO" "${5:-}"
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/git"

cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
if [[ "${1:-} ${2:-}" == "auth status" ]]; then
    exit 0
fi
if [[ "${1:-} ${2:-}" == "pr list" ]]; then
    if [[ "${FAKE_GH_EMPTY_LIST:-0}" == 1 ]]; then
        exit 0
    fi
    if [[ "${FAKE_GH_MULTIPLE_LIST:-0}" == 1 ]]; then
        printf '17\n18\n'
        exit 0
    fi
    printf '17\n'
    exit 0
fi
if [[ "${1:-} ${2:-}" == "pr view" ]]; then
    if [[ "${FAKE_GH_EMPTY_VIEW:-0}" == 1 ]]; then
        exit 0
    fi
    merge_value="${FAKE_GH_MERGE:-$MERGE_COMMIT}"
    if [[ "${FAKE_GH_NO_MERGE:-0}" == 1 ]]; then
        merge_value=
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${FAKE_GH_NUMBER:-17}" \
        "${FAKE_GH_STATE:-MERGED}" \
        "${FAKE_GH_HEAD:-feature/cleanup}" \
        "${FAKE_GH_OWNER:-thelarkbot}" \
        "${FAKE_GH_REPOSITORY:-thelarkbot/project}" \
        "${FAKE_GH_BASE:-main}" \
        "$merge_value"
    exit 0
fi
printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$fake_bin/gh"

export REAL_GIT="$real_git"
export UPSTREAM_REPO="$upstream_repo"
export FORK_REPO="$fork_repo"
export FAKE_GIT_LOG="$fake_git_log"
export FAKE_GH_LOG="$fake_gh_log"
export MERGE_COMMIT="$merge_commit"
export PATH="$fake_bin:$PATH"

if (
    cd "$clone_dir"
    pr-cleanup 17 extra 2>"$test_dir/usage-error"
); then
    fail "pr-cleanup accepted too many arguments"
fi
grep -Fxq 'usage: pr-cleanup [PR]' "$test_dir/usage-error" || fail "pr-cleanup usage was unclear"

git -C "$clone_dir" switch main >/dev/null
: >"$fake_gh_log"
if (
    cd "$clone_dir"
    pr-cleanup 17 2>"$test_dir/default-error"
); then
    fail "pr-cleanup accepted the default branch"
fi
grep -Fq 'refusing to use the default branch' "$test_dir/default-error" || fail "default-branch cleanup error was unclear"
if grep -Fq 'pr view' "$fake_gh_log"; then
    fail "default-branch cleanup queried a pull request"
fi
git -C "$clone_dir" switch feature/cleanup >/dev/null

printf 'dirty\n' >>"$clone_dir/tracked.txt"
: >"$fake_gh_log"
if (
    cd "$clone_dir"
    pr-cleanup 17 2>"$test_dir/dirty-error"
); then
    fail "pr-cleanup accepted tracked changes"
fi
grep -Fq 'tracked changes are present' "$test_dir/dirty-error" || fail "dirty cleanup error was unclear"
if [[ -s "$fake_gh_log" ]]; then
    fail "dirty cleanup reached GitHub"
fi
git -C "$clone_dir" restore tracked.txt

export FAKE_GH_EMPTY_LIST=1
if (
    cd "$clone_dir"
    pr-cleanup 2>"$test_dir/no-pr-error"
); then
    fail "pr-cleanup accepted a branch without a merged pull request"
fi
unset FAKE_GH_EMPTY_LIST
grep -Fq 'no merged pull request found for thelarkbot:feature/cleanup' "$test_dir/no-pr-error" || fail "missing merged PR error was unclear"

export FAKE_GH_MULTIPLE_LIST=1
if (
    cd "$clone_dir"
    pr-cleanup 2>"$test_dir/multiple-pr-error"
); then
    fail "pr-cleanup guessed between multiple merged pull requests"
fi
unset FAKE_GH_MULTIPLE_LIST
grep -Fq 'multiple merged pull requests found' "$test_dir/multiple-pr-error" || fail "multiple merged PR error was unclear"

export FAKE_GH_STATE=OPEN
if (
    cd "$clone_dir"
    pr-cleanup 17 2>"$test_dir/open-pr-error"
); then
    fail "pr-cleanup accepted an open pull request"
fi
unset FAKE_GH_STATE
grep -Fq 'pull request is OPEN, not MERGED' "$test_dir/open-pr-error" || fail "open PR cleanup error was unclear"

for mismatch in head owner repository base; do
    case "$mismatch" in
        head) export FAKE_GH_HEAD=feature/other ;;
        owner) export FAKE_GH_OWNER=another-owner ;;
        repository) export FAKE_GH_REPOSITORY=thelarkbot/another-project ;;
        base) export FAKE_GH_BASE=release ;;
    esac
    if (
        cd "$clone_dir"
        pr-cleanup 17 2>"$test_dir/$mismatch-error"
    ); then
        fail "pr-cleanup accepted a mismatched $mismatch"
    fi
    unset FAKE_GH_HEAD FAKE_GH_OWNER FAKE_GH_REPOSITORY FAKE_GH_BASE
done
grep -Fq 'not thelarkbot/project:feature/cleanup' "$test_dir/head-error" || fail "head mismatch error was unclear"
grep -Fq 'not thelarkbot/project:feature/cleanup' "$test_dir/owner-error" || fail "owner mismatch error was unclear"
grep -Fq 'not thelarkbot/project:feature/cleanup' "$test_dir/repository-error" || fail "repository mismatch error was unclear"
grep -Fq 'targets release, not the upstream default branch main' "$test_dir/base-error" || fail "base mismatch error was unclear"

export FAKE_GH_NO_MERGE=1
if (
    cd "$clone_dir"
    pr-cleanup 17 2>"$test_dir/no-merge-error"
); then
    fail "pr-cleanup accepted a merged PR without a merge commit"
fi
unset FAKE_GH_NO_MERGE
grep -Fq 'has no merge commit' "$test_dir/no-merge-error" || fail "missing merge commit error was unclear"

export FAKE_GH_MERGE="$feature_commit"
: >"$fake_git_log"
if (
    cd "$clone_dir"
    pr-cleanup 17 2>"$test_dir/unpublished-merge-error"
); then
    fail "pr-cleanup deleted a branch before its merge commit reached upstream"
fi
unset FAKE_GH_MERGE
grep -Fq 'merge commit is not present on upstream/main' "$test_dir/unpublished-merge-error" || fail "missing upstream merge error was unclear"
if grep -Eq 'push origin (--delete|HEAD:main)|branch -[dD]' "$fake_git_log"; then
    fail "failed merge verification mutated fork or local branches"
fi

: >"$fake_git_log"
: >"$fake_gh_log"
cleanup_output=$(
    cd "$clone_dir"
    pr-cleanup
)
grep -Fq 'Cleaned up merged pull request #17 and synchronized main.' <<<"$cleanup_output" || fail "success message was unclear"
grep -Fq 'pr list --repo github.com/upstream/project --head feature/cleanup --state merged' "$fake_gh_log" || fail "cleanup did not discover the matching merged PR"
grep -Fq 'pr view 17 --repo github.com/upstream/project' "$fake_gh_log" || fail "cleanup did not inspect the selected PR"
grep -Fq 'fetch upstream main' "$fake_git_log" || fail "cleanup did not fetch upstream main"
grep -Fq 'merge-base --is-ancestor' "$fake_git_log" || fail "cleanup did not verify the merge commit on upstream"
grep -Fq 'push origin HEAD:main' "$fake_git_log" || fail "cleanup did not synchronize the fork default branch"
grep -Fq 'push origin --delete feature/cleanup' "$fake_git_log" || fail "cleanup did not delete the remote feature branch"
grep -Fq 'branch -d feature/cleanup' "$fake_git_log" || fail "cleanup did not try safe local branch deletion first"
grep -Fq 'branch -D feature/cleanup' "$fake_git_log" || fail "cleanup did not handle the squash-merged local branch"

[[ "$($real_git -C "$clone_dir" branch --show-current)" == main ]] || fail "cleanup did not leave the checkout on main"
if $real_git -C "$clone_dir" show-ref --verify --quiet refs/heads/feature/cleanup; then
    fail "local feature branch still exists"
fi
if $real_git ls-remote --exit-code --heads "$fork_repo" feature/cleanup >/dev/null 2>&1; then
    fail "remote feature branch still exists"
fi
[[ "$($real_git -C "$clone_dir" rev-parse main)" == "$merge_commit" ]] || fail "local main was not synchronized"
[[ "$($real_git --git-dir="$fork_repo" rev-parse main)" == "$merge_commit" ]] || fail "fork main was not synchronized"

printf 'merge cleanup tests passed\n'
