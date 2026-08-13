# Archived rc5 PPE handoff

> Historical only. Do not follow this file as an operator runbook.

This handoff described the LEZ v0.2.0-rc5 migration before the public testnet
was reset. Its deployment IDs, wallet paths, polling advice, and transaction
commands are stale. The repository now pins LEZ v0.2.4 at commit
`47eba256479f6f785acbd138834340703cd03401`.

Use the current entry points instead:

- [`README.md`](../README.md#reviewer-entry-points) for local review and CI;
- [`scripts/testnet-evidence.sh`](../scripts/testnet-evidence.sh) for the
  fail-closed, two-approval public-testnet evidence flow;
- [`docs/TESTNET_EVIDENCE.md`](TESTNET_EVIDENCE.md) for the clearly labelled
  historical rc5 evidence archive.

The old instructions remain available in Git history if forensic comparison is
needed. They must not be used to deploy, fund, claim, or record current evidence.
