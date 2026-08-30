# Hardened personal-repository automatic merge

GitHub performs an automatic squash merge only after the native repository
rules and the trusted agent-identity gate both pass. The App may arm or disarm
auto-merge; it never calls a direct-merge endpoint and never checks out or
executes pull-request code. This is the `dev-tools` implementation of the
`peer-agents` profile in the versioned `thelarklan/thelarklan` standard.

## Three-agent quorum

Configure exactly three agent accounts and store their stable numeric GitHub
IDs in private deployment configuration. A bot-authored pull request requires
exact-current-head `APPROVED` reviews from both other agents. An owner-authored
pull request requires any two configured agents. The author, repository owner,
and accounts outside the cohort never substitute for a required agent review.

An eligible pull request is open, non-draft, targets the protected upstream
default branch, and is authored by the owner or one cohort agent. A missing or
dismissed cohort review, cohort `CHANGES_REQUESTED`, an old review commit, a new
head, outside author, API error, incomplete pagination, or ambiguous identity
fails the trusted check. GitHub separately requires repository CI, conversation
resolution, current base, native reviews, and human code-owner approval for
protected paths. The App classifies the complete changed-file list against a
private per-repository exact-path and directory-prefix map. A protected change
also requires the configured human owner's exact-head approval; a routine bot
change publishes failure and remains disarmed if any owner approval exists,
until that approval is dismissed. An owner `CHANGES_REQUESTED` review on a
routine bot change is outside the trusted cohort calculation; GitHub's native
review rule blocks the merge until that request is resolved.

## Trusted App boundary

The private `thelarklan-bot-review-quorum` App receives only:

- metadata read;
- pull requests read and write, solely to inspect reviews and enable or disable
  auto-merge; and
- checks read and write, solely to publish or revoke `bot-review-quorum`.

Do not grant contents write, administration, workflows, secrets, deployments,
ruleset bypass, or any permission that allows a direct merge or push. Keep
account IDs, the protected-path map, the App private key, and installation
configuration outside the repository. Pull-request-controlled files never
define trusted identities or policy.

For every open pull request, the evaluator reads the complete changed-file list
and every review page, then evaluates the latest decisive state for each stable
account ID. Immediately before publishing, it re-reads the pull request, the
complete changed-file list, and the complete review set, and reclassifies the
fresh files. It publishes the result on that exact head. Before auto-merge
reconciliation it re-reads the pull request again and refuses the mutation if
the head or state changed.

With global `QUORUM_AUTO_MERGE=1` and the repository's private `auto_merge`
switch set to `true`, a successful exact-head quorum arms GitHub squash
auto-merge. A failed quorum disarms an existing request. Repositories set to
`false` continue to receive checks without auto-merge mutations, permitting a
staged rollout. GraphQL errors or an unexpected response fail the poll loudly.
A new commit receives no success on its new head and requires fresh reviews.

## Native repository rules

Configure an active default-branch ruleset with no bypass actors that:

- requires pull requests and two approvals;
- dismisses stale approvals and requires approval of the latest reviewable
  push;
- requires code-owner review for the human-owned protected paths;
- requires resolved conversations and a branch current with its base;
- requires `bot-review-quorum` from the expected App plus Jenkins and every
  other mandatory repository CI context;
- permits only squash merge; and
- blocks force pushes and branch deletion.

Enable repository auto-merge only after the App permission update and ruleset
are verified. The App arms individual pull requests; GitHub remains the only
component that merges. Agents and helpers never use a user token, administrator
bypass, or a direct merge command.

## Personal-account limitation

A personal repository cannot synchronously restrict the native approval slots
to the configured agent cohort. The trusted check supplies that identity rule,
but polling once per minute is not an atomic revocation mechanism. Native stale
review, latest-push, two-approval, code-owner, CI, and current-base rules remain
the safety boundary while reconciliation catches up.

Therefore `@thelarklan` does not approve routine bot-authored pull requests, and
no account outside the owner and three-agent cohort receives write access
without a protected policy change. Protected PRs legitimately add the human
approval; the App rechecks the two-agent quorum immediately before arming
auto-merge and disarms it when quorum is later lost. This bounded race is
recorded as a local limitation rather than described as perfectly synchronous.

## Deployment and audit

Start with `QUORUM_AUTO_MERGE=0`. Verify the expected App ID, installed
repositories, account IDs, complete pagination, exact-head success and failure
checks, and the live ruleset. Accept the App pull-request write permission,
enable repository auto-merge, then set `QUORUM_AUTO_MERGE=1` and run one
foreground reconciliation before scheduling the one-minute locked poll. Under
exactly metadata read, pull-request read/write, and checks read/write, confirm
that `enablePullRequestAutoMerge` succeeds and GitHub attributes and performs
the resulting squash merge; also confirm the App has neither contents-write nor
direct-merge capability.

Audit output records repository, PR number, head SHA, author ID, required and
observed reviewer IDs and states, check-run ID, and auto-merge action without
credentials. Tests cover each author rotation, outside and self approvals,
stale or dismissed reviews, later change requests, drafts, wrong bases, missing
heads, auto-merge arm and disarm mutations, and API or response failure.

Until the App permission, every required CI context, and both routine and
protected acceptance scenarios are verified, leave auto-merge unarmed and use
the [human verification checklist](human-verification.md).
