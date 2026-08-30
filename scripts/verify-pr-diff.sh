#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s BASE_REVISION [HEAD_REVISION]\n' "${0##*/}" >&2
    exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage

base=$1
head=${2:-HEAD}

base_commit=$(git rev-parse --verify --end-of-options "${base}^{commit}") || {
    printf 'Cannot resolve base revision: %s\n' "$base" >&2
    exit 1
}
head_commit=$(git rev-parse --verify --end-of-options "${head}^{commit}") || {
    printf 'Cannot resolve head revision: %s\n' "$head" >&2
    exit 1
}
merge_base=$(git merge-base "$base_commit" "$head_commit") || {
    printf 'Cannot find a merge base between %s and %s.\n' "$base" "$head" >&2
    exit 1
}

git diff --check "$merge_base" "$head_commit"
printf 'Verified pull-request diff %s..%s (base %s).\n' \
    "$merge_base" "$head_commit" "$base_commit"
