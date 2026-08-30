#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

# Scheduled providers export their own PR_REVIEW_* settings. None of those
# ambient values should change this test's fake identities, models, or drivers.
unset PR_REVIEW_PROVIDER PR_REVIEW_OWNER PR_REVIEW_REVIEWER \
    PR_REVIEW_MAX_FOLLOWUPS PR_REVIEW_MAX_FAILURES PR_REVIEW_TIMEOUT \
    PR_REVIEW_WORK_ROOT PR_REVIEW_PATH PR_REVIEW_GEMINI_DRIVER \
    PR_REVIEW_CODEX_MODEL PR_REVIEW_CODEX_EFFORT PR_REVIEW_CLAUDE_MODEL \
    PR_REVIEW_CLAUDE_EFFORT PR_REVIEW_ANTIGRAVITY_MODEL \
    PR_REVIEW_ANTIGRAVITY_EFFORT PR_REVIEW_CODEX_BIN PR_REVIEW_CLAUDE_BIN \
    PR_REVIEW_GEMINI_BIN PR_WATCH_OWNER PR_WATCH_REVIEWER \
    PR_WATCH_MAX_FOLLOWUPS PR_WATCH_VERBOSE DEV_TOOLS_HELPER \
    XDG_STATE_HOME XDG_CACHE_HOME

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_arg_pair() {
    local args_file="$1" flag="$2" value="$3" message="$4"
    awk -v flag="$flag" -v value="$value" '
        previous == flag && $0 == value { found = 1 }
        { previous = $0 }
        END { exit !found }
    ' "$args_file" || fail "$message"
}

home_dir="$test_dir/home"
fake_bin="$home_dir/.local/bin"
mkdir -p "$home_dir/.bashrc.d" "$fake_bin"

for provider in codex claude gemini; do
    template="$project_dir/cron/${provider}.crontab"
    grep -Fq 'PR_REVIEW_REVIEWER=CHANGE_ME' "$template" || \
        fail "$(basename "$template") does not require an explicit reviewer"
    grep -Fq 'PR_REVIEW_PATH=CHANGE_ME' "$template" || \
        fail "$(basename "$template") does not require an explicit provider PATH"
done
grep -Fq 'PR_REVIEW_CODEX_MODEL=gpt-5.6-sol PR_REVIEW_CODEX_EFFORT=high' \
    "$project_dir/cron/codex.crontab" || fail "Codex crontab does not pin its model"
grep -Fq 'PR_REVIEW_CLAUDE_MODEL=claude-sonnet-5 PR_REVIEW_CLAUDE_EFFORT=high' \
    "$project_dir/cron/claude.crontab" || fail "Claude crontab does not pin its model"
grep -Fq 'PR_REVIEW_ANTIGRAVITY_MODEL=gemini-3.1-pro-high PR_REVIEW_ANTIGRAVITY_EFFORT=high' \
    "$project_dir/cron/gemini.crontab" || fail "Antigravity crontab does not pin its model"

cat >"$home_dir/.bashrc.d/dev-tools-git.sh" <<'EOF'
pr-watch() {
    if [[ "${PR_WATCH_RECORD_STATE:-1}" == "1" ]]; then
        printf '%s conversation head thread 42\n' "$PR_WATCH_ITEM" >>"$DEV_TOOLS_PR_WATCH_STATE"
    fi
    printf '%s\n' "$PR_WATCH_ITEM"
}
EOF

cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "api" && "$2" == "user" ]]; then
    printf 'review-bot\n'
elif [[ "$1" == "api" && ( "$2" == */reviews* || "${3:-}" == */reviews* ) ]]; then
    if [[ -e "$REVIEW_SUBMITTED" ]]; then
        printf '102\thead-sha\n'
    else
        printf '101\thead-sha\n'
    fi
elif [[ "$1" == "pr" && "$2" == "view" ]]; then
    if [[ -n "${PRE_PROVIDER_FAIL_NUMBER:-}" && "${3:-}" == "$PRE_PROVIDER_FAIL_NUMBER" ]]; then
        printf 'simulated pre-provider head failure\n' >&2
        exit 8
    fi
    if [[ -n "${HEAD_CALLS:-}" ]]; then
        head_calls=0
        [[ ! -e "$HEAD_CALLS" ]] || read -r head_calls <"$HEAD_CALLS"
        head_calls=$((head_calls + 1))
        printf '%s\n' "$head_calls" >"$HEAD_CALLS"
        if [[ "${POST_CONFIRM_FAIL:-0}" == "1" && "$head_calls" -gt 1 ]]; then
            printf 'simulated post-provider head failure\n' >&2
            exit 9
        fi
    fi
    printf 'head-sha\n'
else
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 1
fi
EOF
chmod +x "$fake_bin/gh"

toolchain_bin="$test_dir/toolchain/bin"
mkdir -p "$toolchain_bin"
cat >"$toolchain_bin/test-shell" <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/bash "$@"
EOF
chmod +x "$toolchain_bin/test-shell"

cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env test-shell
set -euo pipefail
if [[ -n "${PROVIDER_CALLS:-}" ]]; then
    call_count=0
    [[ ! -e "$PROVIDER_CALLS" ]] || read -r call_count <"$PROVIDER_CALLS"
    printf '%s\n' "$((call_count + 1))" >"$PROVIDER_CALLS"
fi
printf '%s\n' "$@" >"$PROVIDER_ARGS"
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/codex"

review_marker="$test_dir/review-submitted"
provider_args="$test_dir/provider-args"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=codex \
PR_REVIEW_PATH="$fake_bin:$toolchain_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/repository#7 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_ARGS="$provider_args" \
    "$project_dir/bin/pr-review-cron"

[[ -e "$review_marker" ]] || fail "provider was not invoked"
grep -Fqx 'owner/repository#7 conversation head thread 42' \
    "$home_dir/.local/state/pr-review/pr-watch.seen" || fail "confirmed watcher state was not committed"
grep -Fq 'confirmed review 102 for owner/repository#7 at head-sha' \
    "$home_dir/.local/state/pr-review/cron.log" || fail "review was not confirmed in the log"
assert_arg_pair "$provider_args" --model gpt-5.6-sol "Codex model was not pinned"
assert_arg_pair "$provider_args" --config 'model_reasoning_effort="high"' \
    "Codex reasoning effort was not pinned"
grep -Fq 'perform a separate defect-seeking pass' "$provider_args" || \
    fail "review prompt does not require a defect-seeking pass"
grep -Fq 'tests could pass while documented behavior still fails' "$provider_args" || \
    fail "review prompt does not require test-gap analysis"
grep -Fq 'do not manufacture nits' "$provider_args" || \
    fail "review prompt does not reject quota-driven findings"
grep -Fq 'not as the default outcome' "$provider_args" || \
    fail "review prompt does not set the approval threshold"

cat >"$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$PROVIDER_ARGS"
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/claude"

rm -- "$review_marker"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=claude \
PR_REVIEW_CLAUDE_BIN="$fake_bin/claude" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/claude#8 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_ARGS="$provider_args" \
    "$project_dir/bin/pr-review-cron"
assert_arg_pair "$provider_args" --model claude-sonnet-5 "Claude model was not pinned"
assert_arg_pair "$provider_args" --effort high "Claude effort was not pinned"

cat >"$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$PROVIDER_ARGS"
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/agy"

rm -- "$review_marker"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=gemini \
PR_REVIEW_GEMINI_DRIVER=agy \
PR_REVIEW_GEMINI_BIN="$fake_bin/agy" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/gemini#9 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_ARGS="$provider_args" \
    "$project_dir/bin/pr-review-cron"
assert_arg_pair "$provider_args" --model gemini-3.1-pro-high \
    "Antigravity model was not pinned"
assert_arg_pair "$provider_args" --effort high "Antigravity effort was not pinned"

rm -- "$review_marker"
batch_calls="$test_dir/batch-provider-calls"
batch_items=$'owner/first#10\nowner/fail#11\nowner/third#12'
if HOME="$home_dir" \
    PATH="$fake_bin:$toolchain_bin:/usr/local/bin:/usr/bin:/bin" \
    PR_REVIEW_PROVIDER=codex \
    PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
    PR_REVIEW_TIMEOUT=5s \
    PR_WATCH_ITEM="$batch_items" \
    PR_WATCH_RECORD_STATE=0 \
    PRE_PROVIDER_FAIL_NUMBER=11 \
    REVIEW_SUBMITTED="$review_marker" \
    PROVIDER_ARGS="$provider_args" \
    PROVIDER_CALLS="$batch_calls" \
        "$project_dir/bin/pr-review-cron"; then
    fail "batch with a failed preparation query succeeded"
fi
[[ "$(cat "$batch_calls")" == "2" ]] || \
    fail "a preparation query failure truncated the remaining work batch"
grep -Fq 'preparation query failed for owner/fail#11' \
    "$home_dir/.local/state/pr-review/cron.log" || \
    fail "pre-provider query failure did not name the skipped item"
grep -Fq 'reviewing owner/third#12' "$home_dir/.local/state/pr-review/cron.log" || \
    fail "work after a preparation query failure was not attempted"

rm -- "$review_marker"
head_calls="$test_dir/head-calls"
if HOME="$home_dir" \
    PATH="$fake_bin:$toolchain_bin:/usr/local/bin:/usr/bin:/bin" \
    PR_REVIEW_PROVIDER=codex \
    PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
    PR_REVIEW_TIMEOUT=5s \
    PR_WATCH_ITEM=owner/confirmation#10 \
    REVIEW_SUBMITTED="$review_marker" \
    PROVIDER_ARGS="$provider_args" \
    HEAD_CALLS="$head_calls" \
    POST_CONFIRM_FAIL=1 \
        "$project_dir/bin/pr-review-cron"; then
    fail "post-provider confirmation failure succeeded"
fi
grep -Fq 'confirmation query failed for owner/confirmation#10' \
    "$home_dir/.local/state/pr-review/cron.log" || \
    fail "post-provider confirmation failure aborted without a diagnostic"

rm -- "$review_marker"
failure_calls="$test_dir/failure-calls"
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
count=0
[[ ! -e "$PROVIDER_CALLS" ]] || read -r count <"$PROVIDER_CALLS"
printf '%s\n' "$((count + 1))" >"$PROVIDER_CALLS"
exit 1
EOF
chmod +x "$fake_bin/codex"

for attempt in 1 2; do
    if HOME="$home_dir" \
        PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
        PR_REVIEW_PROVIDER=codex \
        PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
        PR_REVIEW_MAX_FAILURES=2 \
        PR_REVIEW_TIMEOUT=5s \
        PR_WATCH_ITEM=owner/another#8 \
        PR_WATCH_RECORD_STATE=0 \
        REVIEW_SUBMITTED="$review_marker" \
        PROVIDER_CALLS="$failure_calls" \
            "$project_dir/bin/pr-review-cron"; then
        fail "unconfirmed provider run $attempt succeeded"
    fi
done
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=codex \
PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
PR_REVIEW_MAX_FAILURES=2 \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/another#8 \
PR_WATCH_RECORD_STATE=0 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_CALLS="$failure_calls" \
    "$project_dir/bin/pr-review-cron"
[[ "$(cat "$failure_calls")" == "2" ]] || fail "provider retries were not bounded"
grep -Fq 'ESCALATE: owner/another#8 failed 2 consecutive attempt(s)' \
    "$home_dir/.local/state/pr-review/cron.log" || fail "provider failures did not escalate"
grep -Fq 'owner/another#8 at head-sha remains paused after 2 unconfirmed attempt(s)' \
    "$home_dir/.local/state/pr-review/cron.log" || fail "paused item was not named in the log"
if grep -Fq 'owner/another#8 ' "$home_dir/.local/state/pr-review/pr-watch.seen"; then
    fail "failed primary provider state was committed"
fi
if grep -Eq 'owner/(confirmation#10|third#12) ' \
    "$home_dir/.local/state/pr-review/provider-failures"; then
    fail "inactive provider failure state was not pruned"
fi

if HOME="$home_dir" PR_REVIEW_PROVIDER=codex PR_REVIEW_PATH=CHANGE_ME \
    "$project_dir/bin/pr-review-cron" 2>/dev/null; then
    fail "provider PATH placeholder was accepted"
fi

if HOME="$home_dir" PR_REVIEW_PROVIDER=unknown "$project_dir/bin/pr-review-cron" 2>/dev/null; then
    fail "unknown provider succeeded"
fi

printf 'pull request review cron tests passed\n'
