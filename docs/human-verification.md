# Human verification checklist

Use this checklist for each focused dev-tools pull request. Keep the evidence in
the pull-request description or review so it remains attached to the exact head
commit that was verified.

## Contributor record

- State the independently usable behavior introduced by the pull request.
- Record the exact base commit, head commit, and test environment.
- List every automated command run and its observed result.
- Provide numbered manual steps with both expected and observed results.
- Document cleanup, known limitations, and deliberately deferred behavior.
- Confirm that no credentials, tokens, host-home contents, or machine-specific
  state were added.

## Maintainer review

- Confirm the pull request is focused and its head has not changed since the
  recorded verification.
- Repeat the hands-on steps from a disposable checkout or environment.
- Verify failure paths leave the repository in the documented recoverable state.
- Submit the review against the exact head commit.
- Perform the merge deliberately in GitHub only after the evidence is complete.

## Post-merge cleanup

- Run `pr-cleanup` from the merged feature branch.
- Confirm the local default branch and fork default branch match upstream.
- Confirm the verified feature branch is absent both locally and on the fork.
- Preserve any separately retained private source archive; cleanup applies only
  to the reviewed public feature branch.
