#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

loader_count() {
    grep -Fc '# dev-tools bashrc.d loader' "$1"
}

home_with_extension="$test_dir/home-with-extension"
mkdir -p "$home_with_extension"
printf 'export EXISTING_SETTING=kept\n' >"$home_with_extension/.bashrc"

HOME="$home_with_extension" "$project_dir/install.sh" >/dev/null
[[ -f "$home_with_extension/.bashrc.d/dev-tools-git.sh" ]] || fail "helper was not installed"
[[ "$(loader_count "$home_with_extension/.bashrc")" == 1 ]] || fail "loader was not added exactly once"

HOME="$home_with_extension" "$project_dir/install.sh" >/dev/null
[[ "$(loader_count "$home_with_extension/.bashrc")" == 1 ]] || fail "reinstall duplicated the loader"

help_output=$(HOME="$home_with_extension" bash -c 'source "$HOME/.bashrc"; pr-help')
grep -q '^dev-tools commands:$' <<<"$help_output" || fail "help heading is missing"
grep -q 'fork-clone \[HOST/\]OWNER/REPOSITORY' <<<"$help_output" || fail "fork-clone is missing from help"
grep -q '^  fork-sync$' <<<"$help_output" || fail "fork-sync is missing from help"
grep -q 'pr-commit \[--all\] MESSAGE' <<<"$help_output" || fail "pr-commit is missing from help"
grep -q 'pr-amend \[--all\]' <<<"$help_output" || fail "pr-amend is missing from help"
grep -q 'pr-rebase \[BASE\]' <<<"$help_output" || fail "pr-rebase is missing from help"
grep -q 'pr-create \[BASE\]' <<<"$help_output" || fail "pr-create is missing from help"
grep -q 'pr-comment MESSAGE' <<<"$help_output" || fail "pr-comment is missing from help"
grep -q 'pr-cleanup \[PR\]' <<<"$help_output" || fail "pr-cleanup is missing from help"
grep -q '^  pr-help$' <<<"$help_output" || fail "pr-help is missing from help"
if grep -q 'pr-merge' <<<"$help_output"; then
    fail "help advertises an automated merge command"
fi

printf 'export OTHER_EXTENSION=kept\n' >"$home_with_extension/.bashrc.d/other.sh"
HOME="$home_with_extension" "$project_dir/uninstall.sh" >/dev/null
[[ ! -e "$home_with_extension/.bashrc.d/dev-tools-git.sh" ]] || fail "helper was not removed"
[[ -f "$home_with_extension/.bashrc.d/other.sh" ]] || fail "another extension was removed"
grep -Fq '# dev-tools bashrc.d loader' "$home_with_extension/.bashrc" || fail "shared loader was removed"

empty_home="$test_dir/empty-home"
mkdir -p "$empty_home"
printf 'export EXISTING_SETTING=kept\n' >"$empty_home/.bashrc"
HOME="$empty_home" "$project_dir/install.sh" >/dev/null
HOME="$empty_home" "$project_dir/uninstall.sh" >/dev/null

[[ ! -e "$empty_home/.bashrc.d" ]] || fail "empty helper directory was not removed"
if grep -Fq '# dev-tools bashrc.d loader' "$empty_home/.bashrc"; then
    fail "installer-owned loader was not removed"
fi
grep -Fq 'export EXISTING_SETTING=kept' "$empty_home/.bashrc" || fail "existing bashrc content changed"

printf 'install and help tests passed\n'
