# Repository review policy

Standard: review-standard-v2
Approval profile: peer-agents
Human owner: @thelarklan

This repository adopts
[`review-standard-v2`](https://github.com/thelarklan/thelarklan/blob/review-standard-v2/standards/review-standard-v2.md)
from `thelarklan/thelarklan`. The standard is authoritative for common review
intent; this file records only the `dev-tools` implementation and exceptions.

## Approval and protected paths

Routine eligible agent changes follow the three-agent quorum and trusted-App
contract in [automatic-merge.md](automatic-merge.md). After deployment, the App
arms squash auto-merge and routine changes need no human action.

The human owner must approve changes to ownership, review policy, CI and local
verification enforcement, scheduled review execution, the trusted quorum
evaluator and its deployment, or the automatic-merge contract. The local
`CODEOWNERS` file identifies those paths. Agent approvals remain required where
the repository ruleset applies; they do not substitute for human approval on a
protected path. After that content approval, GitHub merges without a separate
human merge action.

Because `@thelarklan` is the sole human owner, protected-path changes must be
agent-authored so that `@thelarklan` remains eligible to approve them. The human
owner must not author such a change until another eligible human owner is added.
No exception authorizes an agent or maintainer to bypass the repository rules.

## Current enforcement

The ruleset audit on 2026-08-29 found an active two-approval gate with stale
review dismissal, latest-push approval, code-owner review, resolved
conversations, strict base updates, squash-only merge, and the
`bot-review-quorum` check. The repository is personal, Jenkins is not a
required status check, and v2 auto-merge reconciliation is not enabled in the
trusted App deployment.

Consequently, automatic merge must remain unarmed. Before this adoption is
declared complete, the owner must add Jenkins as a required status check after
confirming the context is published reliably, grant the trusted App
pull-request write permission without contents or administration access,
install the private protected-path map, and enable v2 reconciliation after a
safe gate test. The live acceptance must prove that
`enablePullRequestAutoMerge` succeeds with exactly metadata read, pull-request
read/write, and checks read/write; that GitHub attributes and performs the
resulting squash merge; and that the App has no contents-write or direct-merge
capability.

## Verification

Run the complete tree suite and verify the final pull-request diff from its
merge base to its exact head:

```bash
bash scripts/verify.sh
bash scripts/verify-pr-diff.sh upstream/main HEAD
git diff --check
```

Record the exact base, head, environment, expected results, and observed results
in the pull-request description. Repeat this evidence after every new commit or
history rewrite.

Manual verification follows [human-verification.md](human-verification.md) and
adds command-specific success, failure, recovery, portability, and destructive-
operation checks when those behaviors change.

## Merge and cleanup

Only squash merge is supported. The trusted App enables or disables auto-merge
after exact-head quorum evaluation; GitHub performs the merge after all native
rules pass. Agents and repository helpers never merge directly or bypass the
gate.

After GitHub reports the pull request merged, run `pr-cleanup` from the verified
feature branch.

## Exceptions

### Jenkins required-check gap

- Rule: required repository CI must pass for the exact reviewed head before
  merge.
- Temporary exception: Jenkins is not yet a required status context in the
  active ruleset.
- Justification: the maintainer must first confirm that the context is
  published reliably for pull-request heads.
- Compensating control: auto-merge remains unarmed; the author and reviewers run
  the complete local suite and merge-base diff check at the recorded exact
  head.
- Owner: `@thelarklan`.
- Review date: 2026-09-04.

### Personal-repository reviewer-identity limitation

- Rule: only the rotating two configured non-author agents satisfy the peer
  quorum at the exact current head.
- Limitation: a personal repository cannot synchronously bind native approval
  slots to those accounts; App polling and GitHub review updates are not one
  atomic operation.
- Compensating control: the App uses stable account IDs and a private
  protected-path map, requires exact-head human approval for protected changes,
  publishes failure and disables auto-merge when human approval exists on a
  routine bot change until that approval is dismissed, re-reads complete
  decisive reviews and the head before arming auto-merge, disarms it when
  quorum is lost, runs at most once per minute, and has no contents-write,
  administration, or direct-merge permission. No outside write collaborator is
  added without protected review.
- Owner: `@thelarklan`.
- Review date: 2026-11-28.

## Repository extension

The repository-specific `pr-cleanup` workflow extends the shared standard. It
verifies the exact merged pull request, synchronizes the default branch, and
removes only the matching local and fork feature branches.
