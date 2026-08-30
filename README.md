# dev-tools

Human-focused shell helpers for a fork-based GitHub pull-request workflow.

The public command set is growing through small, reviewable slices. The current
surface installs the helpers, creates and synchronizes a fork checkout, commits
feature work, performs guarded amend and rebase operations, opens a draft pull
request against the canonical upstream, comments on that pull request, finds
open pull requests that need review, and runs a hardened GitHub App gate that
pins an exact-head three-bot review quorum and reconciles GitHub auto-merge.

## Merge verification

Pull requests are intended to remain small enough for hands-on verification.
Before merging, record the exact manual steps, expected and observed results,
cleanup instructions, known limitations, and behavior deliberately deferred to
a later change.

Until the protected gate is deployed and verified, use the [human verification
checklist](docs/human-verification.md) as the reusable review record and leave
auto-merge unarmed. Under the v2 gate, the trusted App proves that the rotating
two configured non-author agents approved the exact current head, publishes the
required check, and enables or disables squash auto-merge. The personal
repository ruleset continues to enforce native approvals, code-owner approval
for protected paths, CI, current-base, and conversation rules. Routine changes
need no human action; protected changes need human content approval but no
separate merge click. GitHub, not the App or a review agent, performs the merge.
See the [protected automatic merge contract](docs/automatic-merge.md).

The reusable review contract is owned by `thelarklan/thelarklan`; this
repository's [adoption policy](docs/review-policy.md) records only the local
approval profile, protected paths, verification, cleanup, and exceptions.

## Requirements

- Bash
- Git
- A Git author identity (`user.name` and `user.email`, or equivalent standard
  Git author environment variables) for commands that create or rewrite commits
- [GitHub CLI](https://cli.github.com/) authenticated to the target host for
  commands that use the GitHub API (`fork-clone`, `pr-create`, `pr-comment`,
  and `pr-cleanup`)
- ShellCheck for repository verification and the optional Git hooks
- Standard Linux command-line tools (`awk`, `find`, `flock`, `grep`, `install`,
  and `tar`)
- `curl`, `jq`, and OpenSSL for the optional GitHub App quorum evaluator

## Install

```bash
./install.sh
source ~/.bashrc
pr-help
```

The installer copies the helper to `~/.bashrc.d/dev-tools-git.sh`, installs
`pr-review-cron`, `pr-review-quorum`, and `dev-tools-update` in
`~/.local/bin`, creates their lock and log directories, adds a marked
`.bashrc.d` loader to `~/.bashrc` when needed, and prints the installed command
reference. Installed files are replaced atomically. Running the installer
again is safe and does not duplicate the loader.

## Enforce the bot review quorum

The optional `pr-review-quorum` command authenticates as the dedicated
least-privilege GitHub App, polls its installation repositories, publishes the
required `bot-review-quorum` check, and reconciles squash auto-merge. It pins
immutable account IDs. A
bot-authored pull request needs exact-head approvals from the other two cohort
bots; an owner-authored pull request needs exact-head approvals from any two
cohort bots. The repository owner's approval and all outside accounts are
excluded from the quorum.

Credential setup, scheduling, audit output, the personal-repository safety
constraint, and the required ruleset are documented in the [bot review quorum
runbook](docs/review-quorum.md).

## Clone a fork

```bash
fork-clone OWNER/REPOSITORY
fork-clone github.example.com/OWNER/REPOSITORY
fork-clone OWNER/REPOSITORY DIRECTORY
```

`fork-clone` asks GitHub CLI to create the authenticated user's fork, clones
that fork as `origin`, adds the canonical repository as `upstream`, fetches the
upstream refs, and reports the resulting topology. The optional host form uses
the same workflow with GitHub Enterprise.

## Synchronize a fork

From anywhere inside the cloned repository:

```bash
fork-sync
```

`fork-sync` refuses to run when tracked worktree or index changes are present.
It detects the upstream default branch, switches to it when necessary,
fast-forwards it from `upstream`, and pushes that exact branch to `origin`. It
never force-pushes. When `upstream/HEAD` is not cached, the command asks the
upstream Git remote for its symbolic `HEAD`; it does not require GitHub CLI.

## Commit feature work

Create or switch to a feature branch, make a focused change, and run:

```bash
pr-commit "Describe the change"
```

By default, `pr-commit` stages modifications and deletions to tracked files,
creates one commit with the supplied message, and pushes the feature branch to
`origin`. Use `pr-commit --all "Describe the change"` when untracked files are
intentionally part of the commit. The command refuses to commit on the upstream
default branch and never force-pushes.

Creating the commit does not invoke GitHub CLI or require network access.
`fork-clone` caches `upstream/HEAD` so the default-branch safety check also works
offline. If that symbolic ref is missing, `pr-commit` refuses before staging and
shows the command that restores it. After committing, it attempts a normal Git
push. If the push fails, the commit remains local and the error includes the
exact retry command.

## Amend feature work

After changing files that belong in the latest feature commit, run:

```bash
pr-amend
```

`pr-amend` stages tracked modifications and deletions, amends the current
commit without changing its message, waits three seconds so the remote rewrite
can be cancelled, and pushes only with `--force-with-lease`. Use
`pr-amend --all` to include untracked files. The command refuses the upstream
default branch and refuses to rewrite history when nothing is staged.

Set `DEV_TOOLS_FORCE_PUSH_DELAY` to a non-negative number to change the pause;
automated tests use `0`. A lease rejection remains a failure and never falls
back to an unguarded force-push. The guarded retry command is printed before
the delay, so it remains visible when Ctrl-C interrupts the shell. A cancelled
or rejected push leaves the rewritten commit local. Inspect the remote before
retrying after a lease rejection.

## Rebase feature work

From a clean feature branch, rebase onto the upstream default branch with:

```bash
pr-rebase
```

Pass a branch name, such as `pr-rebase release`, to choose another upstream
base. After a successful rebase, the same cancellation window and
`--force-with-lease` protection apply. The command refuses to rebase the
upstream default branch. If conflicts occur, it leaves the rebase in progress
and prints the exact `git rebase --continue` and `git rebase --abort` recovery
commands.

## Open an upstream pull request

From a clean feature branch with at least one commit:

```bash
pr-create
```

`pr-create` pushes the current branch and opens a draft pull request from the
fork to the upstream default branch. Pass a branch name, such as
`pr-create release`, to choose a different upstream base. The command refuses
the default branch and refuses to continue when tracked changes are present. If
the repository contains `.github/pull_request_template.md`, `pr-create` uses it
as the body while continuing to derive the title from commit information.

The upstream repository and fork owner are derived locally from the configured
remote URLs. HTTPS (`https://HOST/OWNER/REPOSITORY.git`), SSH URL
(`ssh://git@HOST/OWNER/REPOSITORY.git`), SCP-style SSH
(`git@HOST:OWNER/REPOSITORY.git`), and `HOST/OWNER/REPOSITORY` forms are
supported. URL-style remotes may include an explicit numeric port, and Git
`url.<base>.insteadOf` rewrites are honored before parsing. GitHub CLI is used
only for authentication and `gh pr create`, not to round-trip metadata already
present in those URLs.

## Comment on the pull request

From the feature branch associated with an open pull request, run:

```bash
pr-comment "Ready for another review"
```

`pr-comment` finds the single open pull request whose head matches the local
fork owner and current branch, then posts the supplied message. It refuses the
default branch, derives both repository identities locally from the configured
remotes, and fails instead of guessing when no matching PR or multiple matching
PRs are open.

## Find pull requests that need review

```bash
pr-watch
```

`pr-watch` searches the configured GitHub account for open pull requests that
need attention from the authenticated GitHub CLI identity. It prints one
`owner/repository#number` per actionable pull request and otherwise prints
nothing. An empty successful result means there is no work; an API failure,
identity mismatch, pagination ceiling, or concurrent invocation exits nonzero
with a fatal diagnostic instead of looking like a quiet poll.

A non-draft pull request authored by someone else is actionable when any of
these conditions holds:

- the identity's latest submitted review is not at the current head SHA;
- the pull request became ready after that review;
- someone replied after the review in an unresolved inline thread opened by
  that identity; or
- an issue comment explicitly requests review with `@LOGIN ... review` or
  `/review LOGIN`.

Ready events and conversation events are deduplicated in a per-reviewer state
file. Conversation follow-ups are capped at two per head SHA by default. The
next new event still surfaces the pull request once, but also writes an
`ESCALATE` diagnostic to stderr so the runner can hand it to a human instead
of continuing an agent loop. A new head SHA resets that follow-up count.

The authenticated login is the reviewer by default. Set
`PR_WATCH_REVIEWER` only as a fail-closed identity assertion: it must match
`gh api user`. Other configuration:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PR_WATCH_OWNER` | `thelarklan` | GitHub user or organization to search. |
| `PR_WATCH_VERBOSE` | `0` | Set to `1` to print the number of open PRs checked. |
| `PR_WATCH_MAX_FOLLOWUPS` | `2` | Autonomous conversation rounds allowed per PR head. |
| `DEV_TOOLS_PR_WATCH_STATE` | Per-reviewer file under the user cache directory | Override the deduplication state path. |

The poller is a reconciliation mechanism, not a model runner. Cron, GitHub
Actions, Claude, Gemini, Codex, Copilot, or another host can invoke the same
command and pass each emitted work item into its own review adapter. Provider
credentials, model selection, prompts, and review submission stay outside this
helper.

## Keep installed tools current

`dev-tools-update` maintains a dedicated checkout at
`~/.local/share/dev-tools/source`, rather than changing a developer worktree.
It accepts updates only from the configured canonical remote and branch,
refuses a dirty checkout, detached head, wrong remote, or rewritten history,
and permits only a fast-forward. It then runs the complete
`bash scripts/verify.sh` surface and calls `install.sh`; an update is recorded
in `~/.local/state/dev-tools-update/deployed` only after both succeed. The
updater shares `~/.cache/pr-review/cron.lock` with the review runners, so an
install cannot overlap an active review. Logs are written to
`~/.local/state/dev-tools-update/cron.log`.

Run it once interactively, then copy the hourly example into `crontab -e` if
automatic deployment is wanted:

```bash
dev-tools-update
cron/dev-tools-update.crontab
```

The updater intentionally does not edit crontab. Existing explicit model and
effort assignments remain pinned. To make a review job follow the defaults in
the verified installed runner, remove only its `PR_REVIEW_*_MODEL` and matching
`PR_REVIEW_*_EFFORT` assignments from the live job. Keep machine-specific
settings such as `PR_REVIEW_REVIEWER`, `PR_REVIEW_PATH`, provider selection,
and executable overrides in crontab. For example, removing
`PR_REVIEW_CLAUDE_MODEL` and `PR_REVIEW_CLAUDE_EFFORT` makes the Claude job use
the defaults in `pr-review-cron` after each successful update.

Useful updater overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `DEV_TOOLS_UPDATE_UPSTREAM` | `https://github.com/thelarklan/dev-tools.git` | Exact canonical fetch URL. |
| `DEV_TOOLS_UPDATE_BRANCH` | `main` | Canonical deployment branch. |
| `DEV_TOOLS_UPDATE_SOURCE` | `~/.local/share/dev-tools/source` | Dedicated deployment checkout. |
| `DEV_TOOLS_UPDATE_LOCK` | `~/.cache/pr-review/cron.lock` | Lock shared with scheduled reviews. |
| `DEV_TOOLS_UPDATE_LOG` | `~/.local/state/dev-tools-update/cron.log` | Update audit log. |
| `DEV_TOOLS_UPDATE_DEPLOYED_STATE` | `~/.local/state/dev-tools-update/deployed` | Last successfully installed commit. |

Automatic updates execute code already merged into the canonical deployment
branch as the local account. Enable the schedule only after that branch's
protection, required CI, and trusted review gate have been deployed and
verified as described in the [protected automatic merge
contract](docs/automatic-merge.md). Passing any example directly to `crontab`
can replace unrelated jobs; use `crontab -e` to add only the intended line.

## Run scheduled agent reviews

`./install.sh` also installs `pr-review-cron` in `~/.local/bin`. The runner
calls `pr-watch`, gives each work item to Codex, Claude, Gemini CLI, or
Antigravity, and accepts the result only after GitHub reports a new review at
the current head. Watcher state is committed only after that confirmation, so
a failed provider run is retried up to three times per pull-request head. Each
unconfirmed attempt is recorded in
`~/.local/state/pr-review/provider-failures`; reaching the limit logs
`ESCALATE` and pauses the item until the head changes or the matching
failure-state line is removed. Failure entries for items no longer emitted by
the watcher are pruned. Events marked `ESCALATE` by the watcher are recorded
and left for a human instead of starting another autonomous review round.

Open `crontab -e` in the matching WSL account and copy the environment and job
lines from one staggered example:

```bash
cron/codex.crontab
cron/claude.crontab
cron/gemini.crontab
```

Replace `PR_REVIEW_REVIEWER=CHANGE_ME` with that WSL account's exact
authenticated GitHub login. Replace `PR_REVIEW_PATH=CHANGE_ME` with the
colon-separated `PATH` from the account's authenticated provider shell so
Node, Python, and repository toolchains remain available under cron; use
absolute directories because crontab environment assignments do not expand
`$HOME`. Each example polls every five minutes and uses `flock` to prevent
overlapping runs. The examples pin Codex to GPT-5.6 Sol with high reasoning,
Claude to Claude Sonnet 5 with high effort, and Antigravity to Gemini 3.7 Flash
High.
Passing an example directly to `crontab` replaces that account's entire
existing crontab, so do that only when replacement is intended. The Gemini
example selects Antigravity's `agy` command; remove
`PR_REVIEW_GEMINI_DRIVER=agy` to use Gemini CLI. Before enabling a schedule,
authenticate `gh` and the selected provider CLI in that WSL account and run
the command once interactively. These adapters grant the provider permission
to use tools without prompting, so use a dedicated account and restrict
`PR_REVIEW_OWNER` to repositories whose pull-request contents you trust.

Logs are written to `~/.local/state/pr-review/cron.log`. Useful overrides:

| Variable | Default | Purpose |
| --- | --- | --- |
| `PR_REVIEW_PROVIDER` | Required | `codex`, `claude`, or `gemini`. |
| `PR_REVIEW_OWNER` | `PR_WATCH_OWNER` or `thelarklan` | Account whose pull requests are reviewed. |
| `PR_REVIEW_REVIEWER` | Authenticated `gh` login | Fail-closed reviewer identity assertion. |
| `PR_REVIEW_MAX_FOLLOWUPS` | `2` | Autonomous conversation rounds per head. |
| `PR_REVIEW_MAX_FAILURES` | `3` | Consecutive unconfirmed provider runs allowed per PR head before pausing. |
| `PR_REVIEW_TIMEOUT` | `45m` | Maximum time for one provider invocation. |
| `PR_REVIEW_WORK_ROOT` | `~/.local/share/pr-review/work` | Provider working directory. |
| `PR_REVIEW_PATH` | Inherited `PATH` | Provider and toolchain search path, after `~/.local/bin`. |
| `PR_REVIEW_GEMINI_DRIVER` | `gemini` | Gemini adapter: `gemini` or `agy`. |
| `PR_REVIEW_CODEX_MODEL` | `gpt-5.6-sol` | Codex model pin. |
| `PR_REVIEW_CODEX_EFFORT` | `high` | Codex reasoning-effort pin. |
| `PR_REVIEW_CLAUDE_MODEL` | `claude-sonnet-5` | Claude model pin. |
| `PR_REVIEW_CLAUDE_EFFORT` | `high` | Claude effort pin. |
| `PR_REVIEW_ANTIGRAVITY_MODEL` | `gemini-3.7-flash-high` | Antigravity model pin. |
| `PR_REVIEW_ANTIGRAVITY_EFFORT` | `high` | Antigravity reasoning-effort pin. |
| `PR_REVIEW_CODEX_BIN` | `codex` on `PATH` | Codex executable override. |
| `PR_REVIEW_CLAUDE_BIN` | `claude` on `PATH` | Claude executable override. |
| `PR_REVIEW_GEMINI_BIN` | Selected driver on `PATH` | Gemini/Antigravity executable override. |

GitHub search exposes at most 1,000 results and the review-thread query reads
at most 100 comments per thread. Reaching either limit fails loudly rather than
silently omitting work.

## Clean up after a merge

Leave auto-merge unarmed until the documented personal-repository gate is
deployed and verified. Dev-tools intentionally does not provide a `pr-merge`
command; the trusted App only arms GitHub squash auto-merge after the rotating
agent quorum passes, and GitHub waits for every other repository rule. After
GitHub reports the pull request merged, stay on its feature branch and run:

```bash
pr-cleanup
```

Pass a pull request number or URL, such as `pr-cleanup 123`, when the branch has
more than one historical merged pull request. Before changing branches or
deleting anything, `pr-cleanup` verifies that the selected upstream pull
request is `MERGED`, its head matches both the local fork repository and current
branch, its base is the upstream default branch, and its merge commit is present
on that branch. It also refuses tracked worktree or index changes, a missing
remote feature branch, or a local feature tip that does not exactly match its
published fork branch.

After those checks, the command fast-forwards the local default branch from
upstream, pushes that branch normally to the fork, lease-protects deletion of
the verified remote feature tip, and deletes the local feature branch. It first
tries Git's safe branch deletion; squash-merged branches require a forced local
deletion because their original commits are not ancestors of the squash commit.
That fallback occurs only after the exact merged pull request, upstream merge
commit, and identical local and published feature tips have been verified.

## Uninstall

```bash
./uninstall.sh
source ~/.bashrc
```

The uninstaller removes the dev-tools helper and quorum evaluator. It preserves
quorum configuration, credentials, logs, and crontab entries for deliberate
manual removal. If other shell extensions
remain in `~/.bashrc.d`, their directory and loader are preserved. If the
directory becomes empty, the installer-owned loader and directory are removed.
The uninstaller does not alter crontabs or delete review/update logs, state, or
the dedicated source checkout; remove scheduled lines with `crontab -e` before
uninstalling them.

## Git hooks

Enable the repository-owned hooks in this checkout with:

```bash
./install-hooks.sh
```

The installer changes only this repository's `core.hooksPath` and refuses to
replace another configured hooks path. The pre-commit hook rejects staged
whitespace errors and runs ShellCheck against the staged versions of changed
shell files, so unstaged edits do not affect the result.

The pre-push hook extracts every distinct revision being pushed into a temporary
snapshot and runs `scripts/verify.sh` there. This verifies the exact published
content rather than any uncommitted worktree changes. Deleting a remote ref does
not run the suite.

## Test

```bash
bash scripts/verify.sh
```

The tests use temporary home directories and local bare Git repositories. They
do not change the caller's shell configuration, GitHub account, or remote
repositories.

Verify the final pull-request diff separately against its upstream base:

```bash
bash scripts/verify-pr-diff.sh upstream/main HEAD
```

The verifier resolves both revisions, computes their merge base, and runs
Git's whitespace validation across the complete final change rather than the
clean worktree surrounding an already-created commit.

## Local Jenkins verification

The repository-owned Declarative `Jenkinsfile` runs on an agent labeled
`linux`. It performs a normal source checkout. For a pull-request build it then
fetches and checks out the exact numbered source head before running ShellCheck
across the shell surface and every `test/*.sh` script, and validates the complete
merge-base-to-head diff against the requested target branch. Branch builds run
the same verification suite on their checked-out revision. New shell tests are
picked up without editing the pipeline.

The pipeline requires Bash, Git, and ShellCheck on the agent. It does not need
developer credentials, a host-home mount, a container-engine socket, or a
project-specific task runner.
