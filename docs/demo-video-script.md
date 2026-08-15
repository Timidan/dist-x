# DistributionX final review video

Record this only after the exact source commit has passed hosted CI, the matching
release assets exist, and the current-testnet evidence manifest has been
published. Keep wallet homes, quote files, eligibility CSVs, bundles, seeds,
destination packets, serialized claims, proofs, and private receipts off screen.

## 0:00 - Exact release and architecture

Show release commit `74f81ab9ee74ba533d3a8fa01cba9f67153f6385`, the `v0.1.0` release URL, and verified `SHA256SUMS`. Explain the
minimal flow:

1. the distributor commits a Merkle root and funds the native distribution pool;
2. each claimant keeps the eligible address, salt, signature, Merkle path, and
   destination keys locally;
3. `claim_ppe` is submitted through LEZ privacy-preserving execution;
4. the public state contains the nullifier and accounting result, not the
   membership witness.

Do not describe `claim_private` as the shipping path. It is an opt-in,
witness-revealing diagnostic fallback and is forbidden by the evidence runner.

## 1:00 - Reviewer package in Basecamp

Install the exact released LGX files into an isolated Logos user directory and
launch Basecamp. Show the distributor wizard and claimant screen using native
settlement. Do not enable custom-token settlement for this evidence run.

For a local rehearsal before release:

```bash
bash scripts/start-basecamp.sh --reset-localnet --clean-user-dir
```

## 2:30 - Real-proof standalone lifecycle

Show the hosted `Standalone LEZ v0.2.4 real-proof E2E` job for the exact commit,
including these markers:

```text
RISC0_DEV_MODE=0
PROVE_LOCAL_OK
VERIFY_OK
CLAIM_OK
E_ALREADY_CLAIMED
DISTRIBUTIONX_E2E_PASS
DISTRIBUTIONX_LOCALNET_E2E_PASS
```

State precisely that the recorded duplicate is rejected by the local claimant
state before rebroadcast. Do not call it an on-chain rejection unless a separate
sequencer-backed replay artifact proves that claim.

## 3:45 - Current public-testnet evidence

Show [`docs/testnet-evidence/v0.1.0/manifest.json`](./testnet-evidence/v0.1.0/manifest.json) and the linked public report produced by:

```bash
bash scripts/testnet-evidence.sh verify
```

Point out the pinned LEZ commit, live RPC fingerprint, deployed program ID,
two distinct distribution IDs, 20 distinct claim transaction/block pairs, and
the exact `5 + 22 = 27` approved write count. State that the execution source is
the immutable `v0.1.0` commit and the read-only export names its newer verifier
commit separately. Do not open the adjacent ignored `target/.../private/` tree.

## 5:00 - Privacy and replay protection

Open the public manifest and summarize one `getTransaction` response without
expanding its large opaque public transaction blob. Show that structured public
evidence contains no eligible address, salt, signature, Merkle path, wallet
seed, destination secret, bundle, serialized claim, or private receipt. Close
with the nullifier invariant and the deterministic `E_ALREADY_CLAIMED` behavior
covered by the program tests.

## Recording acceptance checklist

- exact execution commit equals the hosted-CI `v0.1.0` tag; the separately named
  verifier/docs commit also has green hosted CI;
- both released LGX checksums verify;
- `claim_ppe`, not `claim_private`, is shown and named;
- native settlement is used;
- current evidence has two distributions and 20 distinct included claims;
- no private file, terminal value, QR code, seed, key, or witness appears;
- local duplicate rejection is labelled local unless stronger chain evidence is
  separately available.
