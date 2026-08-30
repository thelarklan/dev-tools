#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
jenkinsfile="$project_dir/Jenkinsfile"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Fq 'pipeline {' "$jenkinsfile" || fail "Declarative pipeline is missing"
grep -Fq 'agent none' "$jenkinsfile" || fail "pipeline should not reserve an agent globally"
grep -Fq "agent { label 'linux' }" "$jenkinsfile" || fail "Validate stage does not target a linux agent"
grep -Fq 'checkout scm' "$jenkinsfile" || fail "source checkout is missing"
grep -Fq 'bash scripts/verify.sh' "$jenkinsfile" || fail "pipeline does not use the repository verification script"
# shellcheck disable=SC2016 # Jenkins expands the literal environment reference.
grep -Fq 'refs/pull/$CHANGE_ID/head' "$jenkinsfile" || fail "pipeline does not fetch the exact pull-request head"
# shellcheck disable=SC2016 # Jenkins expands the literal environment reference.
grep -Fq 'git checkout --detach "refs/remotes/origin/pr/$CHANGE_ID/head"' "$jenkinsfile" || fail "pipeline does not test the exact pull-request head"
# shellcheck disable=SC2016 # Jenkins expands the literal environment reference.
grep -Fq '"+refs/pull/$CHANGE_ID/head:refs/remotes/origin/pr/$CHANGE_ID/head"' "$jenkinsfile" || fail "pipeline does not refresh a reused pull-request ref"
grep -Fq 'bash scripts/verify-pr-diff.sh' "$jenkinsfile" || fail "pipeline does not verify the pull-request diff"
# shellcheck disable=SC2016 # Jenkins expands the literal environment reference.
grep -Fq 'refs/remotes/origin/$CHANGE_TARGET' "$jenkinsfile" || fail "pipeline does not compare against the requested base branch"

verification_script="$project_dir/scripts/verify.sh"
shellcheck_step=$(grep -E '^shellcheck ' "$verification_script" || true)
[[ "$shellcheck_step" == *'bashrc.d/*.sh'* ]] || fail "ShellCheck does not cover every bashrc helper"
[[ "$shellcheck_step" == *'bin/*'* ]] || fail "ShellCheck does not cover every installed executable"
[[ "$shellcheck_step" == *'install.sh'* ]] || fail "ShellCheck does not cover the installer"
[[ "$shellcheck_step" == *'uninstall.sh'* ]] || fail "ShellCheck does not cover the uninstaller"
[[ "$shellcheck_step" == *'install-hooks.sh'* ]] || fail "ShellCheck does not cover the hook installer"
[[ "$shellcheck_step" == *'.githooks/*'* ]] || fail "ShellCheck does not cover every Git hook"
[[ "$shellcheck_step" == *'scripts/*.sh'* ]] || fail "ShellCheck does not cover every repository script"
[[ "$shellcheck_step" == *'test/*.sh'* ]] || fail "ShellCheck does not cover every shell test"
grep -Fq 'for test_script in test/*.sh; do' "$verification_script" || fail "verification does not discover every shell test"
# shellcheck disable=SC2016
grep -Fq 'bash "$test_script"' "$verification_script" || fail "verification does not execute discovered shell tests"

if grep -Eiq 'podman\.sock|docker\.sock|credentials' "$jenkinsfile" ||
    grep -Eiq "sh[[:space:]]+['\"]+[[:space:]]*just([[:space:]]|['\"])" "$jenkinsfile" ||
    grep -Eiq '^[[:space:]]*just([[:space:]]|$)' "$jenkinsfile"; then
    fail "Jenkinsfile requests a forbidden local-CI dependency"
fi

printf 'Jenkinsfile contract tests passed\n'
