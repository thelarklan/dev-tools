# Bot review quorum

`pr-review-quorum` is a polling evaluator for the private
`thelarklan-bot-review-quorum` GitHub App. It never checks out pull-request code,
pushes, approves, directly merges, or changes repository settings. Its
installation permissions are limited to metadata read, pull requests read and
write, and checks read and write. Pull-request write exists only to enable or
disable GitHub auto-merge.

For each open pull request in a repository owned by `thelarklan`, the evaluator
publishes the `bot-review-quorum` check on the exact pull-request head. For a
bot-authored pull request, both other bot IDs must have a latest decisive
`APPROVED` review for that same head. For an owner-authored pull request, any two
of the three bot IDs must approve the exact head. Approvals by the author,
`thelarklan`, or any account outside the cohort never count. Authors outside the
owner-plus-bot set, drafts, other base branches, stale approvals, dismissals,
change requests, a review-read error, and a head change during evaluation do not
receive a successful result. With reconciliation enabled, success arms squash
auto-merge and failure disarms an existing request.

## Trusted deployment configuration

Download a private key from the App's GitHub settings and store it outside every
repository. On the one trusted WSL account that runs the evaluator:

```bash
install -d -m 700 "$HOME/.config/dev-tools"
install -m 600 /mnt/c/Users/CHANGE_ME/Downloads/thelarklan-bot-review-quorum.pem \
  "$HOME/.config/dev-tools/thelarklan-bot-review-quorum.pem"
```

Create `~/.config/dev-tools/pr-review-quorum.env` with mode `600`:

```bash
QUORUM_APP_ID=4752010
QUORUM_INSTALLATION_ID=157289427
QUORUM_OWNER_ID=166922787
QUORUM_BOT_IDS=270192887,104110997,320627233
QUORUM_PRIVATE_KEY_FILE="$HOME/.config/dev-tools/thelarklan-bot-review-quorum.pem"
QUORUM_PROTECTED_PATHS_FILE="$HOME/.config/dev-tools/protected-paths.json"
QUORUM_AUTO_MERGE=0
```

Create the protected-path map beside it with mode `600`. This private copy is
the bootstrap and drift-detection boundary; pull-request code cannot weaken the
classification that applies to itself. Paths ending in `/` are directory
prefixes and every other value is exact. Wildcards, parent traversal, missing
repository entries, and empty arrays are rejected.

```json
{
  "thelarklan/thelarklan": {
    "auto_merge": true,
    "paths": [
      ".github/CODEOWNERS", ".github/workflows/", "standards/",
      "templates/", "scripts/", "test/", "docs/review-policy.md"
    ]
  },
  "thelarklan/dev-tools": {
    "auto_merge": false,
    "paths": [
      ".github/CODEOWNERS", ".github/pull_request_template.md",
      ".github/workflows/", "AGENTS.md", "Jenkinsfile",
      "docs/automatic-merge.md", "docs/human-verification.md",
      "docs/review-policy.md", "docs/review-quorum.md", ".githooks/",
      "install-hooks.sh", "install.sh", "uninstall.sh", "scripts/", "test/",
      "bin/pr-review-cron", "bin/pr-review-quorum", "cron/"
    ]
  },
  "thelarklan/wsl-tools": {
    "auto_merge": false,
    "paths": [".github/CODEOWNERS", ".github/workflows/", "AGENTS.md", "docs/review-policy.md"]
  },
  "thelarklan/podman-tools": {
    "auto_merge": false,
    "paths": [".github/CODEOWNERS", ".github/workflows/", "AGENTS.md", "docs/review-policy.md"]
  },
  "thelarklan/jenkins-controller": {
    "auto_merge": false,
    "paths": [".github/CODEOWNERS", ".github/workflows/", "AGENTS.md", "Jenkinsfile", "docs/review-policy.md"]
  },
  "thelarklan/lol": {
    "auto_merge": false,
    "paths": [".github/CODEOWNERS", ".github/workflows/", "AGENTS.md", "docs/review-policy.md"]
  }
}
```

Add every installed repository explicitly before the App polls it, and keep the
map aligned with the base branch's protected `CODEOWNERS` rules. The per-repo
`auto_merge` switch permits staged rollout: enable the canonical source first,
then change `dev-tools` to `true` only when its v2 pilot is ready. A protected
PR requires an exact-head approval from the configured owner ID in addition to
the two agent reviews. A routine bot PR fails if the owner approves it.
That failure disables any armed auto-merge request and remains until the owner
approval is dismissed.

Then enforce its mode:

```bash
chmod 600 "$HOME/.config/dev-tools/pr-review-quorum.env" \
  "$HOME/.config/dev-tools/protected-paths.json"
```

The immutable account-ID mapping is:

| Account | GitHub ID |
| --- | ---: |
| `thelarklan` | `166922787` |
| `larkbot-codex` | `270192887` |
| `larkbot-claude` | `104110997` |
| `larkbot-gemini` | `320627233` |

Do not put the private key, installation token, environment file, or a copy of
the private key in Git. The evaluator refuses a key readable by group or other
users. It obtains a short-lived installation token for every poll, streams the
authorization header to curl over standard input so the token is absent from
process arguments, and does not write that token to disk or logs.

Keep `QUORUM_AUTO_MERGE=0` until the App permission update, repository ruleset,
and repository-level auto-merge setting have been verified. Run one foreground
audit before scheduling:

```bash
QUORUM_CONFIG_FILE="$HOME/.config/dev-tools/pr-review-quorum.env" \
  pr-review-quorum
```

Each output line is JSON containing the repository, pull request, exact head,
author and reviewer IDs, conclusion, check-run ID, and auto-merge action. It
contains no credential. After a safe test, change `QUORUM_AUTO_MERGE=1`, run
another foreground reconciliation, and only then schedule it. Run exactly one
evaluator instance; the template uses `flock` and polls once per minute.

The append-only audit log is not rotated automatically. Configure `logrotate`
or equivalent retention for `~/.local/state/pr-review-quorum/cron.log` based on
the repository's pull-request volume and required audit window.

## Personal-repository ruleset

The App installation does not create rulesets. For each default branch, create
an active ruleset with no bypass actors that:

- requires pull requests and two approvals;
- dismisses stale approvals and requires approval of the latest reviewable
  push;
- requires all conversations to be resolved;
- requires the branch to be current before merging;
- requires code-owner review for protected paths;
- requires `bot-review-quorum` specifically from
  `thelarklan-bot-review-quorum` and every repository CI check; and
- permits only squash merge.

GitHub auto-merge may be enabled only after the evaluator has published a check
in that repository and the ruleset is verified on a safe pull request. A
personal repository cannot natively restrict the two approval slots to a team.
The App check prevents an owner or outside approval from satisfying the bot
quorum, but polling is not an instantaneous revocation mechanism. Therefore,
`thelarklan` must not approve a routine bot-authored pull request, and outside
accounts must not receive write access without protected review. The evaluator
disables an armed request when its next complete evaluation loses quorum.

An API failure before the evaluator can enumerate a repository or pull request
causes a nonzero poll but cannot revoke a previously published check until API
access recovers. The native two-approval rule and the owner-approval constraint
are the safety boundary during that interval.

The evaluator supplies one required check and reconciles the auto-merge request;
GitHub remains the only component that performs the merge. Do not grant the App
contents write, administration, workflows, secrets, deployments, or bypass
permission.
