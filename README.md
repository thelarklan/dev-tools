# dev-tools

Human-focused shell helpers for a fork-based GitHub pull-request workflow.

The public command set is growing through small, reviewable slices. The current
surface installs the helpers, creates and synchronizes a fork checkout, commits
feature work, performs guarded amend and rebase operations, opens a draft pull
request against the canonical upstream, and comments on that pull request.

## Human verification

Pull requests are intended to remain small enough for hands-on verification.
Before merging, record the exact manual steps, expected and observed results,
cleanup instructions, known limitations, and behavior deliberately deferred to
a later change. Merging remains a deliberate maintainer action in GitHub.

## Requirements

- Bash
- Git
- A Git author identity (`user.name` and `user.email`, or equivalent standard
  Git author environment variables) for commands that create or rewrite commits
- [GitHub CLI](https://cli.github.com/) authenticated to the target host for
  commands that use the GitHub API (`fork-clone`, `pr-create`, `pr-comment`,
  and `pr-cleanup`)
- Standard Linux command-line tools (`awk`, `find`, `grep`, and `install`)

## Install

```bash
./install.sh
source ~/.bashrc
pr-help
```

The installer copies the helper to `~/.bashrc.d/dev-tools-git.sh`, adds a
marked `.bashrc.d` loader to `~/.bashrc` when needed, and prints the installed
command reference. Running the installer again is safe and does not duplicate
the loader.

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
the default branch and refuses to continue when tracked changes are present.

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

## Clean up after a merge

Merging remains a deliberate maintainer action in GitHub after review and
hands-on verification. Dev-tools intentionally does not provide a `pr-merge`
command. After GitHub reports the pull request merged, stay on its feature
branch and run:

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

The uninstaller removes only the dev-tools helper. If other shell extensions
remain in `~/.bashrc.d`, their directory and loader are preserved. If the
directory becomes empty, the installer-owned loader and directory are removed.

## Test

```bash
shellcheck bashrc.d/*.sh install.sh uninstall.sh test/*.sh
bash test/install_help_test.sh
bash test/fork_sync_test.sh
bash test/pr_create_test.sh
bash test/rewrite_comment_test.sh
bash test/cleanup_test.sh
bash test/jenkinsfile_test.sh
```

The tests use temporary home directories and local bare Git repositories. They
do not change the caller's shell configuration, GitHub account, or remote
repositories.

## Local Jenkins verification

The repository-owned Declarative `Jenkinsfile` runs on an agent labeled
`linux`. It performs a normal source checkout, runs ShellCheck across the shell
surface, and executes every `test/*.sh` script. New shell tests are picked up
without editing the pipeline.

The pipeline requires Bash, Git, and ShellCheck on the agent. It does not need
developer credentials, a host-home mount, a container-engine socket, or a
project-specific task runner.
