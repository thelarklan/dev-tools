#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

repo=$test_dir/repo
git init -q -b main "$repo"
git -C "$repo" config user.name 'Diff Test'
git -C "$repo" config user.email 'diff-test@example.com'
printf 'base\n' >"$repo/example.txt"
git -C "$repo" add example.txt
git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)

git -C "$repo" switch -qc feature
printf 'clean change\n' >>"$repo/example.txt"
git -C "$repo" commit -qam clean
(
    cd -- "$repo"
    bash "$project_dir/scripts/verify-pr-diff.sh" "$base" HEAD
) >/dev/null || fail "clean pull-request diff was rejected"

printf 'trailing whitespace  \n' >>"$repo/example.txt"
git -C "$repo" commit -qam whitespace
if (
    cd -- "$repo"
    bash "$project_dir/scripts/verify-pr-diff.sh" "$base" HEAD
) >"$test_dir/whitespace-output" 2>&1; then
    fail "pull-request diff accepted trailing whitespace"
fi
grep -Fq 'trailing whitespace' "$test_dir/whitespace-output" || fail "whitespace failure was unclear"

sed -i 's/trailing whitespace  $/trailing whitespace/' "$repo/example.txt"
git -C "$repo" commit -qam fix
(
    cd -- "$repo"
    bash "$project_dir/scripts/verify-pr-diff.sh" "$base" HEAD
) >/dev/null || fail "corrected pull-request diff remained invalid"

if (
    cd -- "$repo"
    bash "$project_dir/scripts/verify-pr-diff.sh" missing HEAD
) >"$test_dir/base-output" 2>&1; then
    fail "missing base revision was accepted"
fi
grep -Fq 'Cannot resolve base revision' "$test_dir/base-output" || fail "missing-base failure was unclear"

printf 'pull-request diff verification tests passed\n'
