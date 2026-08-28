# Repository agent instructions

These instructions govern automated changes in this repository. They are
limited to the Git and pull-request lifecycle; use the repository's existing
documentation, tests, and code as the authority for implementation behavior.

## Start from a safe repository state

- Inspect the current branch, worktree, remotes, and upstream default branch
  before changing files. Preserve unrelated work.
- Treat `thelarklan/dev-tools` as the canonical upstream and contribute through
  a fork such as `thelarkbot/dev-tools`.
- Synchronize a clean local default branch with upstream, then create a focused
  feature branch. Do not commit directly to the default branch.
- Never add credentials, tokens, private keys, user-home contents, or other
  machine-specific state.

Use the repository-provided helpers when they are installed. Equivalent safe
Git and GitHub operations are acceptable when the helpers are unavailable.

## Keep each change reviewable

- Make one independently useful change per pull request.
- Keep command behavior, `pr-help`, README guidance, tests, and the Jenkins
  contract aligned when a change affects them.
- Review the complete diff and run `git diff --check` before committing.
- Prefer `pr-commit "MESSAGE"` for tracked changes. Use
  `pr-commit --all "MESSAGE"` only when every untracked file is intentionally
  part of the change.
- Use normal pushes for new commits. Never force-push the default branch and
  never use an unguarded force-push. Use `pr-amend` or `pr-rebase` when a
  feature-branch rewrite is necessary because they protect the push with a
  lease.

## Verify before requesting review

Discover the required checks from the current README, Jenkinsfile, and CI
configuration. Run every applicable required check whose tooling is available.
The current complete local surface is:

```bash
shellcheck bashrc.d/*.sh install.sh uninstall.sh test/*.sh
bash test/install_help_test.sh
bash test/fork_sync_test.sh
bash test/pr_create_test.sh
bash test/rewrite_comment_test.sh
bash test/cleanup_test.sh
bash test/jenkinsfile_test.sh
git diff --check
```

- Run the required checks at the exact commit that will be reviewed and record
  the revision and results in the pull-request description.
- Open the pull request as a draft. Include the summary, automated and manual
  verification, expected results, cleanup, known limitations, and deferred
  behavior.
- Do not mark the pull request ready, request review, or re-request review while
  an available required local or remote check is running or failing.
- If a required check cannot run because its tool or environment is genuinely
  unavailable, keep the pull request in draft, record the limitation, and wait
  for explicit maintainer direction before requesting review.
- After new commits or a history rewrite, rerun the applicable checks at the
  new head, update the recorded evidence, and wait for available remote checks
  again.

## Review, merge, and cleanup

- Respond to review findings with focused changes and leave blocking threads
  for the reviewer to resolve or confirm.
- Do not approve or directly merge your own pull request. A maintainer may
  perform the deliberate squash merge through GitHub after review and
  exact-head verification. Alternatively, GitHub may merge automatically under
  the fail-closed three-agent quorum and trusted-check contract documented in
  `docs/automatic-merge.md`. Review agents must not publish or imitate that
  trusted check, use an administrator bypass, or merge with a personal token.
  This repository intentionally has no `pr-merge` helper.
- After GitHub reports the pull request merged, run `pr-cleanup [PR]` from its
  feature branch. Let the command verify the exact merged pull request,
  synchronize the default branch, and remove only the verified local and fork
  feature branches.
