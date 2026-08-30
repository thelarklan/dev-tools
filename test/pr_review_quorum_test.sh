#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

# shellcheck source=bin/pr-review-quorum
source "$project_dir/bin/pr-review-quorum"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

bot_codex=270192887
bot_claude=104110997
bot_gemini=320627233
owner=166922787
bots="[$bot_codex,$bot_claude,$bot_gemini]"
head_sha='exact-head'
pull_file="$test_dir/pull.json"
reviews_file="$test_dir/reviews.json"

write_pull() {
    local author="$1" draft="${2:-false}" base="${3:-main}" state="${4:-open}"
    jq -cn --argjson author "$author" --argjson draft "$draft" --arg base "$base" \
        --arg state "$state" --arg head "$head_sha" \
        '{state:$state,draft:$draft,user:{id:$author},head:{sha:$head},base:{ref:$base}}' >"$pull_file"
}

write_reviews() {
    jq -cn "$1" >"$reviews_file"
}

conclusion() {
    evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner" | jq -r '.conclusion'
}

review() {
    local id="$1" login="$2" state="$3" commit="$4" sequence="$5"
    jq -cn --argjson id "$sequence" --argjson user_id "$id" --arg login "$login" \
        --arg state "$state" --arg commit "$commit" --arg submitted "2026-08-28T10:00:0${sequence}Z" \
        '{id:$id,user:{id:$user_id,login:$login},state:$state,commit_id:$commit,submitted_at:$submitted}'
}

assert_success_for_author() {
    local author="$1" first_id="$2" first_login="$3" second_id="$4" second_login="$5"
    local first second
    write_pull "$author"
    first=$(review "$first_id" "$first_login" APPROVED "$head_sha" 1)
    second=$(review "$second_id" "$second_login" APPROVED "$head_sha" 2)
    write_reviews "[$first,$second]"
    [[ "$(conclusion)" == success ]] || fail "rotation failed for author $author"
}

assert_success_for_author "$bot_codex" "$bot_claude" larkbot-claude "$bot_gemini" larkbot-gemini
assert_success_for_author "$bot_claude" "$bot_codex" larkbot-codex "$bot_gemini" larkbot-gemini
assert_success_for_author "$bot_gemini" "$bot_codex" larkbot-codex "$bot_claude" larkbot-claude

write_pull "$bot_codex"
claude_review=$(review "$bot_claude" larkbot-claude APPROVED "$head_sha" 1)
owner_review=$(review "$owner" thelarklan APPROVED "$head_sha" 2)
write_reviews "[$claude_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'owner approval substituted for a bot approval'

author_review=$(review "$bot_codex" larkbot-codex APPROVED "$head_sha" 1)
write_reviews "[$author_review,$claude_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'author or owner approval counted toward quorum'

gemini_review=$(review "$bot_gemini" larkbot-gemini APPROVED "$head_sha" 3)
write_reviews "[$claude_review,$gemini_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'human approval was accepted on a routine bot change'
[[ "$(evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner" true true | jq -r '.conclusion')" == success ]] || \
    fail 'protected bot change rejected exact-head agent and human approvals'

write_reviews "[$claude_review,$gemini_review]"
[[ "$(evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner" true true | jq -r '.conclusion')" == failure ]] || \
    fail 'protected bot change passed without human approval'
[[ "$(evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner" false false | jq -r '.conclusion')" == failure ]] || \
    fail 'unknown protected-path classification passed'

stale_review=$(review "$bot_gemini" larkbot-gemini APPROVED old-head 2)
write_reviews "[$claude_review,$stale_review]"
[[ "$(conclusion)" == failure ]] || fail 'approval on an old head counted'

dismissed_review=$(review "$bot_gemini" larkbot-gemini DISMISSED "$head_sha" 2)
write_reviews "[$claude_review,$dismissed_review]"
[[ "$(conclusion)" == failure ]] || fail 'dismissed approval counted'

gemini_approval=$(review "$bot_gemini" larkbot-gemini APPROVED "$head_sha" 1)
gemini_change=$(review "$bot_gemini" larkbot-gemini CHANGES_REQUESTED "$head_sha" 3)
write_reviews "[$claude_review,$gemini_approval,$gemini_change]"
[[ "$(conclusion)" == failure ]] || fail 'latest change request did not override approval'

write_pull 999999999
write_reviews "[$claude_review,$gemini_approval]"
[[ "$(conclusion)" == failure ]] || fail 'outside author passed the cohort gate'

write_pull "$owner"
write_reviews "[$claude_review,$gemini_approval]"
[[ "$(conclusion)" == success ]] || fail 'owner-authored pull request did not accept two bot approvals'
[[ "$(evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner" true true | jq -r '.conclusion')" == failure ]] || \
    fail 'owner-authored protected change passed without an eligible human approver'

write_reviews "[$claude_review,$owner_review]"
[[ "$(conclusion)" == failure ]] || fail 'owner approval counted on an owner-authored pull request'

write_pull "$bot_codex" true
write_reviews "[$claude_review,$gemini_approval]"
[[ "$(conclusion)" == failure ]] || fail 'draft pull request passed'

write_pull "$bot_codex" false release
[[ "$(conclusion)" == failure ]] || fail 'pull request to another base passed'

write_pull "$bot_codex"
jq 'del(.head.sha)' "$pull_file" >"$test_dir/missing-head.json"
mv "$test_dir/missing-head.json" "$pull_file"
empty_claude_review=$(review "$bot_claude" larkbot-claude APPROVED '' 1)
empty_gemini_review=$(review "$bot_gemini" larkbot-gemini APPROVED '' 2)
write_reviews "[$empty_claude_review,$empty_gemini_review]"
missing_head_evaluation=$(evaluate_quorum "$pull_file" "$reviews_file" main "$bots" "$owner")
[[ "$(jq -r '.conclusion' <<<"$missing_head_evaluation")" == failure ]] || \
    fail 'missing head and empty review commit IDs passed the quorum gate'
[[ "$(jq -r '[.observed[].exact_head] | any' <<<"$missing_head_evaluation")" == false ]] || \
    fail 'empty review commit ID was marked as an exact-head approval'

protected_config='{"thelarklan/example":{"auto_merge":true,"paths":[".github/","AGENTS.md"]}}'
[[ "$(classify_protected_change thelarklan/example '[".github/workflows/verify.yml"]' "$protected_config")" == true ]] || \
    fail 'protected directory prefix did not match'
[[ "$(classify_protected_change thelarklan/example '["AGENTS.md"]' "$protected_config")" == true ]] || \
    fail 'protected exact path did not match'
[[ "$(classify_protected_change thelarklan/example '["README.md"]' "$protected_config")" == false ]] || \
    fail 'routine path was classified as protected'
if classify_protected_change thelarklan/missing '["README.md"]' "$protected_config" \
    >/dev/null 2>&1; then
    fail 'repository missing protected-path configuration was accepted'
fi
[[ "$(repository_auto_merge_enabled thelarklan/example "$protected_config")" == true ]] || \
    fail 'repository auto-merge policy was not read'

fake_bin="$test_dir/fake-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
method=''
previous=''
data=''
authorization=\$(cat)
[[ "\$authorization" == "Authorization: Bearer "* ]] || {
    printf 'fake curl did not receive authorization on stdin\n' >&2
    exit 1
}
for argument in "\$@"; do
    if [[ "\$argument" == *'Authorization: Bearer '* || "\$argument" == installation-token ]]; then
        printf 'authorization token leaked into fake curl argv\n' >&2
        exit 1
    fi
    if [[ "\$previous" == -X ]]; then
        method="\$argument"
    elif [[ "\$previous" == --data-binary ]]; then
        data="\$argument"
    fi
    previous="\$argument"
done
url="\${!#}"
case "\$method \$url" in
    *'/app/installations/157289427/access_tokens')
        printf '%s\n' '{"token":"installation-token"}'
        ;;
    *'/installation/repositories?per_page=100&page=1')
        printf '%s\n' '{"repositories":[{"full_name":"thelarklan/example","owner":{"id":166922787},"default_branch":"main"}]}'
        ;;
    *'/repos/thelarklan/example/pulls?state=open&per_page=100&page=1')
        printf '%s\n' '[{"number":7}]'
        ;;
    *'/repos/thelarklan/example/pulls/7/reviews?per_page=100&page=1')
        review_head=exact-head
        if [[ "\${FAKE_HEAD_CHANGE:-0}" == 1 ]]; then
            review_head=head-B
        fi
        if [[ "\${FAKE_APPROVALS:-complete}" == complete ]]; then
            printf '[{"id":1,"user":{"id":104110997,"login":"larkbot-claude"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-08-28T10:00:01Z"},{"id":2,"user":{"id":320627233,"login":"larkbot-gemini"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-08-28T10:00:02Z"}]\n' "\$review_head" "\$review_head"
        elif [[ "\${FAKE_APPROVALS:-complete}" == owner ]]; then
            printf '[{"id":1,"user":{"id":104110997,"login":"larkbot-claude"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-08-28T10:00:01Z"},{"id":2,"user":{"id":320627233,"login":"larkbot-gemini"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-08-28T10:00:02Z"},{"id":3,"user":{"id":166922787,"login":"thelarklan"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-08-28T10:00:03Z"}]\n' "\$review_head" "\$review_head" "\$review_head"
        else
            printf '[{"id":1,"user":{"id":104110997,"login":"larkbot-claude"},"state":"APPROVED","commit_id":"%s","submitted_at":"2026-08-28T10:00:01Z"}]\n' "\$review_head"
        fi
        ;;
    *'/repos/thelarklan/example/pulls/7/files?per_page=100&page=1')
        if [[ "\${FAKE_HEAD_CHANGE:-0}" == 1 ]]; then
            file_calls=0
            [[ ! -f "\$FAKE_FILE_COUNTER" ]] || read -r file_calls <"\$FAKE_FILE_COUNTER"
            file_calls=\$((file_calls + 1))
            printf '%s\n' "\$file_calls" >"\$FAKE_FILE_COUNTER"
            if ((file_calls == 1)); then
                printf '%s\n' '[{"filename":"README.md"}]'
            else
                printf '%s\n' '[{"filename":".github/workflows/verify.yml"}]'
            fi
        else
            printf '%s\n' '[{"filename":"README.md"}]'
        fi
        ;;
    *'/repos/thelarklan/example/pulls/7')
        pull_head=exact-head
        if [[ "\${FAKE_HEAD_CHANGE:-0}" == 1 ]]; then
            pull_calls=0
            [[ ! -f "\$FAKE_PULL_COUNTER" ]] || read -r pull_calls <"\$FAKE_PULL_COUNTER"
            pull_calls=\$((pull_calls + 1))
            printf '%s\n' "\$pull_calls" >"\$FAKE_PULL_COUNTER"
            if ((pull_calls == 1)); then
                pull_head=head-A
            else
                pull_head=head-B
            fi
        fi
        if [[ "\${FAKE_APPROVALS:-complete}" == complete ]]; then
            printf '{"node_id":"PR_test","auto_merge":null,"changed_files":%s,"state":"open","draft":false,"html_url":"https://github.com/thelarklan/example/pull/7","user":{"id":270192887},"head":{"sha":"%s"},"base":{"ref":"main"}}\n' "\${FAKE_CHANGED_FILES:-1}" "\$pull_head"
        else
            printf '{"node_id":"PR_test","auto_merge":{"enabled_by":{"login":"app"}},"changed_files":%s,"state":"open","draft":false,"html_url":"https://github.com/thelarklan/example/pull/7","user":{"id":270192887},"head":{"sha":"%s"},"base":{"ref":"main"}}\n' "\${FAKE_CHANGED_FILES:-1}" "\$pull_head"
        fi
        ;;
    *'/repos/thelarklan/example/commits/'*'/check-runs?check_name=bot-review-quorum&filter=latest')
        printf '%s\n' '{"check_runs":[]}'
        ;;
    'POST '*'/repos/thelarklan/example/check-runs')
        printf '%s\n' '{"id":9001}'
        ;;
    'POST '*'/graphql')
        printf '%s\n' "\$data" >>"\$GRAPHQL_LOG"
        if [[ "\${FAKE_GRAPHQL_ERROR:-0}" == 1 ]]; then
            printf '%s\n' '{"errors":[{"message":"simulated mutation rejection"}]}'
        elif [[ "\$data" == *enablePullRequestAutoMerge* ]]; then
            printf '%s\n' '{"data":{"enablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":{"enabledAt":"2026-08-28T10:00:03Z","mergeMethod":"SQUASH"}}}}}'
        else
            printf '%s\n' '{"data":{"disablePullRequestAutoMerge":{"pullRequest":{"autoMergeRequest":null}}}}'
        fi
        ;;
    *)
        printf 'unexpected fake curl request: %s %s\n' "\$method" "\$url" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$fake_bin/curl"

private_key="$test_dir/app.pem"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$private_key" 2>/dev/null
chmod 600 "$private_key"
protected_paths_file="$test_dir/protected-paths.json"
printf '%s\n' '{"thelarklan/example":{"auto_merge":true,"paths":[".github/","AGENTS.md"]}}' >"$protected_paths_file"
chmod 600 "$protected_paths_file"
config_file="$test_dir/quorum.env"
cat >"$config_file" <<EOF
QUORUM_APP_ID=4752010
QUORUM_INSTALLATION_ID=157289427
QUORUM_OWNER_ID=166922787
QUORUM_BOT_IDS=270192887,104110997,320627233
QUORUM_PRIVATE_KEY_FILE=$private_key
QUORUM_CURL_BIN=$fake_bin/curl
QUORUM_AUTO_MERGE=1
QUORUM_PROTECTED_PATHS_FILE=$protected_paths_file
EOF
chmod 600 "$config_file"

graphql_log="$test_dir/graphql.log"
integration_output=$(GRAPHQL_LOG="$graphql_log" QUORUM_CONFIG_FILE="$config_file" \
    "$project_dir/bin/pr-review-quorum")
[[ "$(jq -r '.conclusion' <<<"$integration_output")" == success ]] || \
    fail 'end-to-end polling fixture did not publish success'
[[ "$(jq -r '.check_run_id' <<<"$integration_output")" == 9001 ]] || \
    fail 'end-to-end polling fixture did not record the published check run'
[[ "$(jq -r '.auto_merge_action' <<<"$integration_output")" == armed ]] || \
    fail 'successful exact-head quorum did not arm auto-merge'
grep -Fq 'enablePullRequestAutoMerge' "$graphql_log" || \
    fail 'successful exact-head quorum did not use the enable mutation'

head_change_pull_counter="$test_dir/head-change-pulls"
head_change_file_counter="$test_dir/head-change-files"
before_mutations=$(wc -l <"$graphql_log")
integration_output=$(FAKE_HEAD_CHANGE=1 \
    FAKE_PULL_COUNTER="$head_change_pull_counter" \
    FAKE_FILE_COUNTER="$head_change_file_counter" \
    GRAPHQL_LOG="$graphql_log" QUORUM_CONFIG_FILE="$config_file" \
    "$project_dir/bin/pr-review-quorum")
[[ "$(jq -r '.head' <<<"$integration_output")" == head-B ]] || \
    fail 'head-change fixture did not publish against the fresh head'
[[ "$(jq -r '.protected' <<<"$integration_output")" == true ]] || \
    fail 'head-change evaluation reused the stale routine classification'
[[ "$(jq -r '.conclusion' <<<"$integration_output")" == failure ]] || \
    fail 'head-change evaluation passed without fresh protected approval'
[[ "$(<"$head_change_file_counter")" == 2 ]] || \
    fail 'changed-file list was not re-read before publishing'
[[ "$(wc -l <"$graphql_log")" == "$before_mutations" ]] || \
    fail 'stale routine classification armed auto-merge on the fresh protected head'

integration_output=$(FAKE_APPROVALS=missing GRAPHQL_LOG="$graphql_log" \
    QUORUM_CONFIG_FILE="$config_file" "$project_dir/bin/pr-review-quorum")
[[ "$(jq -r '.conclusion' <<<"$integration_output")" == failure ]] || \
    fail 'missing exact-head approval did not publish failure'
[[ "$(jq -r '.auto_merge_action' <<<"$integration_output")" == disarmed ]] || \
    fail 'lost exact-head quorum did not disarm auto-merge'
grep -Fq 'disablePullRequestAutoMerge' "$graphql_log" || \
    fail 'lost exact-head quorum did not use the disable mutation'

integration_output=$(FAKE_APPROVALS=owner GRAPHQL_LOG="$graphql_log" \
    QUORUM_CONFIG_FILE="$config_file" "$project_dir/bin/pr-review-quorum")
[[ "$(jq -r '.conclusion' <<<"$integration_output")" == failure ]] || \
    fail 'routine bot change with owner approval did not publish failure'
[[ "$(jq -r '.auto_merge_action' <<<"$integration_output")" == disarmed ]] || \
    fail 'routine bot change with owner approval did not disarm auto-merge'

if FAKE_GRAPHQL_ERROR=1 GRAPHQL_LOG="$graphql_log" \
    QUORUM_CONFIG_FILE="$config_file" "$project_dir/bin/pr-review-quorum" \
    >"$test_dir/graphql-error-output" 2>"$test_dir/graphql-error"; then
    fail 'GraphQL mutation error did not fail the poll'
fi
grep -Fq 'GitHub rejected the auto-merge armed mutation' \
    "$test_dir/graphql-error" || fail 'GraphQL mutation failure was not diagnosed'

set +e
integration_output=$(FAKE_CHANGED_FILES=2 GRAPHQL_LOG="$graphql_log" \
    QUORUM_CONFIG_FILE="$config_file" "$project_dir/bin/pr-review-quorum" \
    2>"$test_dir/file-list-error")
integration_status=$?
set -e
((integration_status != 0)) || fail 'incomplete pull-request file list did not fail the poll'
[[ "$(jq -r '.conclusion' <<<"$integration_output")" == failure ]] || \
    fail 'incomplete pull-request file list did not publish failure'
grep -Fq 'incomplete file list for thelarklan/example#7' "$test_dir/file-list-error" || \
    fail 'incomplete pull-request file list was not diagnosed'

jq '.["thelarklan/example"].auto_merge = false' "$protected_paths_file" \
    >"$test_dir/protected-paths.next"
mv "$test_dir/protected-paths.next" "$protected_paths_file"
chmod 600 "$protected_paths_file"
before_mutations=$(wc -l <"$graphql_log")
integration_output=$(GRAPHQL_LOG="$graphql_log" QUORUM_CONFIG_FILE="$config_file" \
    "$project_dir/bin/pr-review-quorum")
[[ "$(jq -r '.auto_merge_action' <<<"$integration_output")" == disabled-for-repository ]] || \
    fail 'repository rollout switch did not suppress auto-merge'
[[ "$(wc -l <"$graphql_log")" == "$before_mutations" ]] || \
    fail 'disabled repository still received an auto-merge mutation'

printf 'pull request quorum tests passed\n'
