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

fake_bin="$test_dir/bin"
fake_gh_log="$test_dir/gh.log"
upstream_work="$test_dir/upstream-work"
upstream_repo="$test_dir/upstream.git"
fork_repo="$test_dir/fork.git"
clone_dir="$test_dir/clone"

mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_GH_LOG"

if [[ "${1:-} ${2:-}" == "auth status" ]]; then
    if [[ "${FAKE_GH_AUTH_FAIL:-0}" == 1 ]]; then
        exit 1
    fi
    exit 0
fi

if [[ "${1:-} ${2:-}" == "pr create" ]]; then
    printf 'https://github.com/upstream/project/pull/1\n'
    exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$fake_bin/gh"

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

origin_url=https://github.com/thelarkbot/project.git
upstream_url=git@github.com:upstream/project.git
git -C "$clone_dir" remote set-url origin "$origin_url"
git -C "$clone_dir" remote set-url --push origin "$fork_repo"
git -C "$clone_dir" remote set-url upstream "$upstream_url"

export FAKE_GH_LOG="$fake_gh_log"
export PATH="$fake_bin:$PATH"

[[ "$(_dev_git_parse_remote 'https://github.com/upstream/project.git')" == github.com/upstream/project ]] || fail "HTTPS remote was not parsed"
[[ "$(_dev_git_parse_remote 'ssh://git@github.com/upstream/project.git')" == github.com/upstream/project ]] || fail "SSH URL remote was not parsed"
[[ "$(_dev_git_parse_remote 'ssh://git@ssh.github.com:443/upstream/project.git')" == ssh.github.com/upstream/project ]] || fail "SSH URL remote with a port was not parsed"
[[ "$(_dev_git_parse_remote 'https://github.com:8443/upstream/project.git')" == github.com/upstream/project ]] || fail "HTTPS remote with a port was not parsed"
[[ "$(_dev_git_parse_remote 'git@github.com:upstream/project.git')" == github.com/upstream/project ]] || fail "SCP-style SSH remote was not parsed"
[[ "$(_dev_git_parse_remote 'github.example.com/upstream/project')" == github.example.com/upstream/project ]] || fail "host selector was not parsed"
if _dev_git_parse_remote 'ssh://git@github.com:not-a-port/upstream/project.git' 2>"$test_dir/invalid-port-error"; then
    fail "nonnumeric remote port was accepted"
fi
grep -Fq 'remote URL must identify HOST/OWNER/REPOSITORY' "$test_dir/invalid-port-error" || fail "invalid-port error was unclear"
if _dev_git_parse_remote 'https://github.com/upstream/too/many/parts.git' 2>"$test_dir/parser-error"; then
    fail "invalid remote path was accepted"
fi
grep -Fq 'remote URL must identify HOST/OWNER/REPOSITORY' "$test_dir/parser-error" || fail "invalid remote error was unclear"

if (
    cd "$test_dir"
    pr-commit 2>"$test_dir/usage-error"
); then
    fail "pr-commit accepted a missing message"
fi
grep -Fxq 'usage: pr-commit [--all] MESSAGE' "$test_dir/usage-error" || fail "usage was not reported before repository requirements"

export FAKE_GH_AUTH_FAIL=1
: >"$fake_gh_log"
git -C "$clone_dir" switch -c feature/example >/dev/null
git -C "$clone_dir" config --unset user.name
git -C "$clone_dir" config --unset user.email
printf 'identity guard\n' >>"$clone_dir/tracked.txt"
previous_head=$(git -C "$clone_dir" rev-parse HEAD)
if (
    cd "$clone_dir"
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
    unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
    pr-commit "Missing identity must fail" 2>"$test_dir/identity-error"
); then
    fail "pr-commit accepted a missing Git author identity"
fi
[[ "$(git -C "$clone_dir" rev-parse HEAD)" == "$previous_head" ]] || fail "missing identity created a commit"
git -C "$clone_dir" diff --cached --quiet || fail "missing identity staged changes"
grep -Fq 'Git user identity is not configured' "$test_dir/identity-error" || fail "missing identity error was unclear"
git -C "$clone_dir" restore tracked.txt
git -C "$clone_dir" config user.name Test
git -C "$clone_dir" config user.email test@example.com

printf 'tracked change\n' >>"$clone_dir/tracked.txt"
printf 'leave untracked\n' >"$clone_dir/untracked.txt"
if (
    cd "$clone_dir"
    pr-commit "Misplaced option" --all 2>"$test_dir/misplaced-option-error"
); then
    fail "pr-commit accepted a misplaced --all option"
fi
grep -Fxq 'usage: pr-commit [--all] MESSAGE' "$test_dir/misplaced-option-error" || fail "misplaced --all error was unclear"
git -C "$clone_dir" diff --cached --quiet || fail "invalid arguments staged changes"
(
    cd "$clone_dir"
    pr-commit "Update tracked file" >/dev/null
)

git --git-dir="$fork_repo" show-ref --verify --quiet refs/heads/feature/example || fail "feature branch was not pushed"
git -C "$clone_dir" ls-files --error-unmatch untracked.txt >/dev/null 2>&1 && fail "default commit included an untracked file"

(
    cd "$clone_dir"
    pr-commit --all "Add untracked file" >/dev/null
)
git -C "$clone_dir" ls-files --error-unmatch untracked.txt >/dev/null || fail "--all did not include the untracked file"
[[ ! -s "$fake_gh_log" ]] || fail "pr-commit invoked GitHub CLI"

previous_head=$(git -C "$clone_dir" rev-parse HEAD)
printf 'commit before failed push\n' >>"$clone_dir/tracked.txt"
git -C "$clone_dir" remote set-url origin "$test_dir/missing-fork.git"
git -C "$clone_dir" remote set-url --push origin "$test_dir/missing-fork.git"
if (
    cd "$clone_dir"
    pr-commit "Keep local commit after push failure" 2>"$test_dir/push-error"
); then
    fail "pr-commit reported success when push failed"
fi
[[ "$(git -C "$clone_dir" rev-parse HEAD)" != "$previous_head" ]] || fail "failed push discarded the local commit"
[[ "$(git -C "$clone_dir" log -1 --format=%s)" == 'Keep local commit after push failure' ]] || fail "failed push did not preserve the expected commit"
grep -Fq 'commit created locally but push failed' "$test_dir/push-error" || fail "failed-push recovery was unclear"
git -C "$clone_dir" remote set-url origin "$origin_url"
git -C "$clone_dir" remote set-url --push origin "$fork_repo"

git -C "$clone_dir" remote set-head upstream --delete
printf 'do not stage without upstream HEAD\n' >>"$clone_dir/tracked.txt"
previous_head=$(git -C "$clone_dir" rev-parse HEAD)
if (
    cd "$clone_dir"
    pr-commit "Cannot verify branch offline" 2>"$test_dir/missing-head-error"
); then
    fail "pr-commit accepted a missing upstream/HEAD"
fi
[[ "$(git -C "$clone_dir" rev-parse HEAD)" == "$previous_head" ]] || fail "missing upstream/HEAD created a commit"
git -C "$clone_dir" diff --cached --quiet || fail "missing upstream/HEAD staged changes"
grep -Fq 'upstream/HEAD is not set' "$test_dir/missing-head-error" || fail "missing upstream/HEAD error was unclear"
git -C "$clone_dir" restore tracked.txt
git -C "$clone_dir" symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/main
[[ ! -s "$fake_gh_log" ]] || fail "offline pr-commit checks invoked GitHub CLI"
unset FAKE_GH_AUTH_FAIL

git -C "$clone_dir" switch main >/dev/null
printf 'do not commit\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    pr-commit "Unsafe default-branch commit" 2>"$test_dir/default-error"
); then
    fail "pr-commit accepted the default branch"
fi
grep -Fq 'refusing to use the default branch' "$test_dir/default-error" || fail "default-branch error was unclear"
git -C "$clone_dir" restore tracked.txt

if (
    cd "$clone_dir"
    pr-create release 2>"$test_dir/explicit-base-error"
); then
    fail "pr-create accepted the default branch with an explicit base"
fi
grep -Fq 'refusing to use the default branch' "$test_dir/explicit-base-error" || fail "explicit-base default-branch error was unclear"
if grep -Fq 'pr create ' "$fake_gh_log"; then
    fail "pr-create reached GitHub from the default branch"
fi

git -C "$clone_dir" switch feature/example >/dev/null
printf 'dirty\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    # shellcheck disable=SC2119
    pr-create 2>"$test_dir/dirty-error"
); then
    fail "pr-create accepted tracked changes"
fi
grep -Fq 'tracked changes are present' "$test_dir/dirty-error" || fail "dirty-worktree error was unclear"
git -C "$clone_dir" restore tracked.txt

git -C "$clone_dir" remote set-url upstream not-a-remote
if (
    cd "$clone_dir"
    # shellcheck disable=SC2119
    pr-create 2>"$test_dir/invalid-upstream-error"
); then
    fail "pr-create accepted an invalid upstream repository"
fi
grep -Fq 'could not determine the upstream repository' "$test_dir/invalid-upstream-error" || fail "invalid upstream error was unclear"
git -C "$clone_dir" remote set-url upstream "$upstream_url"

git -C "$clone_dir" remote set-url origin not-a-remote
if (
    cd "$clone_dir"
    # shellcheck disable=SC2119
    pr-create 2>"$test_dir/invalid-origin-error"
); then
    fail "pr-create accepted an invalid origin owner"
fi
grep -Fq 'could not determine the origin repository owner' "$test_dir/invalid-origin-error" || fail "invalid origin-owner error was unclear"
git -C "$clone_dir" remote set-url origin "$origin_url"

: >"$fake_gh_log"
git -C "$clone_dir" config url."git@github.com:".insteadOf gh:
git -C "$clone_dir" remote set-url origin gh:thelarkbot/project
git -C "$clone_dir" remote set-url --push origin "$fork_repo"
git -C "$clone_dir" remote set-url upstream gh:upstream/project
[[ "$(git -C "$clone_dir" config --get remote.origin.url)" == gh:thelarkbot/project ]] || fail "alias regression setup did not preserve the raw origin URL"
[[ "$(git -C "$clone_dir" remote get-url origin)" == git@github.com:thelarkbot/project ]] || fail "Git did not resolve the origin URL alias"
[[ "$(git -C "$clone_dir" remote get-url upstream)" == git@github.com:upstream/project ]] || fail "Git did not resolve the upstream URL alias"

(
    cd "$clone_dir"
    # shellcheck disable=SC2119
    pr-create >/dev/null
)
grep -Fq 'pr create --repo github.com/upstream/project --base main --head thelarkbot:feature/example --fill --draft' "$fake_gh_log" || fail "draft upstream pull request was not created correctly"
grep -Fq 'auth status' "$fake_gh_log" || fail "pr-create did not check GitHub CLI authentication"
if grep -Fq 'repo view' "$fake_gh_log"; then
    fail "pr-create used GitHub API calls for local remote metadata"
fi

mkdir -p "$clone_dir/.github"
mkdir -p "$clone_dir/nested"
printf '## Verification\n' >"$clone_dir/.github/pull_request_template.md"
: >"$fake_gh_log"
(
    cd "$clone_dir/nested"
    # shellcheck disable=SC2119
    pr-create >/dev/null
)
grep -Fq "pr create --repo github.com/upstream/project --base main --head thelarkbot:feature/example --fill --body-file $clone_dir/.github/pull_request_template.md --draft" "$fake_gh_log" || fail "pr-create did not populate the repository pull-request template"

printf 'commit and PR creation tests passed\n'
