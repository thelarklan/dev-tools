# Protected automatic merge

Automatic merge is safe only when GitHub, rather than a repository helper or
review agent, performs the merge after a fail-closed identity and revision
gate. Enabling repository auto-merge by itself is not sufficient.

## Three-agent quorum

Configure one merge cohort containing exactly three GitHub accounts. Store and
compare their stable GitHub account IDs; logins are display labels and may be
renamed.

For a pull request to be eligible:

- it is open, non-draft, and targets the protected upstream default branch;
- its author is one member of the configured cohort;
- each of the other two cohort members has a latest review state of `APPROVED`;
- both approvals were submitted against the pull request's current head SHA;
- the author does not count toward the review quorum;
- all required CI checks, including Jenkins, pass for that same head SHA; and
- every other repository rule, including conversation resolution and the
  up-to-date-branch policy, is satisfied.

A pull request authored outside the cohort is ineligible. A missing review,
`CHANGES_REQUESTED` review, new head commit, API error, pagination ceiling, or
ambiguous identity keeps the gate from passing. Two reviews from one account
never substitute for approvals from both required accounts.

For example, if agent A authors the pull request, agents B and C must approve
its exact current head. The rule rotates with the author.

## Trusted check

Run the quorum evaluator as a dedicated GitHub App. Grant it only the metadata
and pull-request read access needed to inspect the pull request and reviews,
plus checks write access to publish a `bot-review-quorum` check run. Do not give
the app contents write, pull-request write, administration, or merge authority.
The evaluator must not check out or execute code from the pull request.

Publish the check against the inspected head SHA. Re-read the pull request head
immediately before publishing success and refuse success if it changed during
evaluation. A later push naturally leaves the new head without a successful
quorum check and requires both non-author agents to review again.

Configure an active GitHub ruleset for the default branch that:

- requires changes to arrive through a pull request;
- requires `bot-review-quorum` from the dedicated GitHub App;
- requires the Jenkins check and all other repository CI checks;
- dismisses stale approvals and requires approval of the latest reviewable push;
- requires review conversations to be resolved;
- requires the branch to be current with the protected base before merging;
- allows only the intended merge method; and
- has no bypass actors.

Enable GitHub auto-merge only after that ruleset is active and verified. The
quorum evaluator supplies evidence; it never merges. GitHub performs the merge
only after every required check and rule is satisfied. Repository helpers and
agents must not use administrator bypasses or recreate this decision with a
high-privilege personal token.

## Deployment and audit

Keep the three account IDs and expected GitHub App identity in trusted
deployment configuration, not in pull-request-controlled executable input.
Log the repository, pull request number, head SHA, author ID, required reviewer
IDs, observed review IDs and states, and resulting check-run ID for each
evaluation without logging credentials.

Test the gate before relying on it. At minimum, verify that it refuses an
outside author, an author approval, one missing reviewer, an approval on an old
head, a later change request, failing or pending CI, a changed head during
evaluation, and API or pagination failure. Also verify the successful rotation
for each of the three possible authors.

Until the trusted check and active ruleset are deployed and verified, use the
[human verification checklist](human-verification.md) and merge deliberately.
