# Applied-fixes behavioral tests

The test driver extracts all three Bash steps from `apply-signed-fixes.yaml` with
`yq` and executes them unchanged in disposable Git repositories. The only fake
external boundary is GitHub's API. Its requests, returned verification objects,
and mutation count are recorded locally. No token or network access is needed.

Production signing stays inline. The privileged job may not run code from the
consumer checkout; `test-lint-signed-commit.sh` continues to enforce its action
inventory, content digests, and credential boundaries. Test helpers and extracted
scripts live outside the consumer repository, so the committed payload contains
only the intended consumer changes.

## Behavioral contract

- Tip checks use the event head and only require a signature for this lane's own
  applied-fixes headline. They also run when the replacement invocation has no patch.
- Ordinary no-change inputs make no API call from the commit step. Already-applied
  fixes still verify the head instead of treating an empty change set as sufficient.
- Changes preserve exact bytes and paths, including binary and large files, and
  bind the mutation to the repository, branch, message, and expected head.
- Unsupported file modes, failed Git discovery, conflicting patches, stale heads,
  failed API calls, and malformed responses fail instead of reporting completion.
- Signature verification must succeed after every successful commit mutation.
  An unsigned, absent, or failed verification cannot report a successful job.

[`createCommitOnBranch`](https://docs.github.com/en/graphql/reference/commits#createcommitonbranch)
updates the remote branch as part of the commit mutation.
The subsequent verification is therefore a post-publication check: a failed read
does not prove the remote branch stayed unchanged. The fake API records the write
before returning its commit identity, and negative verification tests assert that
the job fails without retrying or performing another mutation. The stronger
verification-before-publication requirement remains on Actions #1007.

The fixtures prove caller behavior at an API boundary, not GitHub's real signature
issuance or a consumer rollout. Existing hosted signer jobs supply separate live
evidence. Deliberately weakened workflow copies prove these tests detect missing
verification and incorrect request identity; they never change the checked-in
workflow or refresh its security digests.
