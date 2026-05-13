# DistributionX Write-Up

## Commitment Scheme

DistributionX parses an eligibility CSV into amount buckets and computes `leaf = H_LEAF(address, bucket_id, salt)` for each row. The on-chain commitment is the fixed-depth Merkle root. The bucket table is hashed separately and bound into the airdrop id and encrypted bundle associated data.

## Claim Uniqueness Scope

On-chain enforcement is per nullifier rather than per recipient. Each claim publishes `nullifier = H_NULL(salt) = SHA256("logos-distributionx/null-v1" || salt)` (`crates/distributionx-tree/src/hash.rs:26-31`). The nullifier binds to the salt only, not to the address. The LEZ/SPEL account model stores a `NullifierRecord` at PDA seed `["nullifier", airdrop_id, nullifier]` (`methods/guest/src/bin/distributionx.rs:381, 472`), and a second initialization with the same seeds returns `E_ALREADY_CLAIMED` (`methods/guest/src/bin/distributionx.rs:390-394`).

The committed Merkle leaf binds `(address, bucket_id, salt)` together (`crates/distributionx-tree/src/hash.rs:3-10`), so a valid claim corresponds to exactly one committed row in the tree.

Address-level uniqueness is enforced at the CSV ingest stage, not by the on-chain program. The parser in `crates/distributionx-tree/src/csv.rs:25-33` uses a `HashSet<address>` to reject duplicate addresses with `CliDuplicateAddr` before the tree is built. If a distributor bypassed `parse_csv` and constructed leaves directly with the same address under two different salts, the on-chain program would honor both claims because the two rows would have two different nullifiers.

The accurate reading of "each recipient can claim once" is therefore: on the chain, once per committed leaf which is once per nullifier; in practice, once per address, with the CSV dedup as the load-bearing piece for the recipient-level reading.

## Privacy Model

The targeted privacy property is that on-chain observers should not learn the eligible address, row salt, claim signature, or Merkle path from a valid claim transcript. The program exposes two claim instructions and the property is not currently demonstrably met under either, for distinct reasons.

**`claim` (Risc0 receipt path, `methods/guest/src/bin/distributionx.rs:379-466`).** The instruction args are `airdrop_id`, `nullifier`, `receipt_bytes`, and `now_unix`. Verification consumes a Risc0 Groth16 receipt and reads the journal. The public journal contains only `airdrop_id`, `merkle_root`, `bucket_id`, `nullifier`, and `claim_destination_commitment` (`crates/distributionx-circuit/src/journal.rs:3-10`). The witness fields are private inputs to the zkVM and never appear in the journal or in the instruction data, so the property would hold for this path. However, the instruction also takes `#[account(mut)] recipient` (line 384) and credits its balance directly. LEZ requires the program to claim ownership of any modified default-owner account in the post-state (`.scaffold/cache/repos/lez/.../nssa/src/validated_state_diff.rs:240-254`). A shielded one-time destination commitment has no signer to authorize that ownership transfer, so the instruction fails with `InvalidProgramBehavior`. The receipt-based `claim` is therefore not runnable under the shielded reviewer flow as currently designed.

**`claim_private` (in-program verifier, `methods/guest/src/bin/distributionx.rs:470-553`).** This instruction runs the witness verification inside the program rather than inside the zkVM, so the witness fields have to be passed as instruction args. The IDL at `idl/distributionx.json:204-216` lists them: `claimant_address`, `salt`, `claim_sig`, `merkle_siblings`, `merkle_path_is_right`. The generated FFI submits via `NSSATransaction::Public(tx)` at every send site (`src/generated/distributionx_ffi.rs:249, 315, 388, 471, 535`), so those arguments are part of the public transaction transcript and an observer with RPC `getTransaction` access can recover them. The credit lands on the `nullifier_record` PDA (program-owned via `#[account(init, pda = ...)]`), which avoids the ownership-claim rule that breaks `claim`. `claim_private` is therefore the only path that runs end-to-end in the shielded reviewer flow, and the witness is in the chain transcript on this path.

The privacy property is acknowledged as not currently met. Two tracked follow-ups would each independently restore it: (1) refactor `claim` to credit the `nullifier_record` PDA instead of an arbitrary recipient account, mirroring `claim_private`'s credit pattern at lines 540-552; (2) wire `claim_private` through `NSSATransaction::PrivacyPreserving` (LEZ ships this variant in the vendored sdk at `.scaffold/cache/repos/lez/.../nssa/src/privacy_preserving_transaction/`) so the witness args are shielded from chain observers. Either fix is sufficient. Both require touching the program, the IDL mirrors, the generated FFI, and a fresh proof generation.

**A note on naming.** The `claim_private` identifier predates this audit and is misleading in its current form. The instruction is the in-program verifier described above and does not provide observer privacy for the witness under its current submission path. A clearer identifier would be something like `claim_inline` (because the verifier runs inline in the LEZ program rather than inside the zkVM). The rename is deferred because it touches the LEZ program, all three IDL mirrors (`idl/`, `crates/distributionx-program/idl/`, `crates/distributionx-bindings/generated/`), the generated client and FFI in `src/generated/`, scripts, tests, and several doc sections (about 17 files in total). The documentation above describes what the instruction actually does; the rename is tracked alongside the privacy follow-ups.

The claim signature binds `logos-distributionx/claim-v2 || airdrop_id || claim_destination_commitment` (`crates/distributionx-wallet-ref/src/sign.rs:1-7`). A relayer or observer can resubmit the same proof to the same commitment, but changing the destination commitment invalidates the in-circuit Ed25519 verification.

## Bucket Anonymity

The `bucket_id` is public. It appears in the Risc0 journal (`crates/distributionx-circuit/src/journal.rs:7`) and as an explicit arg to `claim_private`. The `bucket_table` (the amount schedule) is public init data submitted with `init_airdrop` (`idl/distributionx.json:61-62`).

Observer unlinkability is therefore bounded by the per-bucket anonymity set size. The probability that a given on-chain claim corresponds to a particular eligible recipient is at most 1/k per bucket, where k is the recipient count for that bucket. Two failure modes follow directly:

- A singleton bucket (k=1) reveals the recipient by amount. The observer learns exactly which eligibility row claimed.
- A small bucket (k=2 or k=3) shrinks the anonymity set sharply. Repeated claims, correlated timing, or out-of-band metadata can push the observer toward a single candidate.

The CLI surfaces this risk during CSV ingest. `inspect-csv` emits a warning when the smallest bucket has fewer than 8 recipients (`crates/distributionx-cli/src/commands.rs:1110-1114`), and the `pad-csv --min-per-bucket N` command lets a distributor top up small buckets to a desired baseline. The CSV parser also caps the table at 32 buckets and 50,000 recipients (`crates/distributionx-tree/src/csv.rs:40-50`).

The on-chain program does not enforce a minimum k at `init_airdrop`. Bucket anonymity is an accepted residual leakage; the distributor is trusted to choose a bucket schedule that fits the privacy budget they want for their list.

## Salt Threat Model

**Generation.** Salts are 32 bytes per row drawn from the OS CSPRNG via `OsRng.fill_bytes` (`crates/distributionx-tree/src/bundle.rs:44-48`). The bundle builder rejects same-bundle collisions before producing the leaf. The entropy assumption is that `rand::rngs::OsRng` (backed by getrandom on Linux and macOS) is unbroken.

**Distribution.** Each row is sealed for its intended recipient. The row plaintext `{address, bucket_id, salt, merkle_path}` is encrypted with ChaCha20-Poly1305 AEAD; the key and nonce come from X25519 ECDH against the recipient's claim key (the recipient's ed25519 pubkey converted to x25519 via libsodium), passed through HKDF-SHA-256 with bundle context binding (`crates/distributionx-tree/src/bundle.rs:68-105`). Only the intended recipient's claim key can decrypt their row.

**Storage.** The reviewer flow stores the wallet seed in a `wallet.seed` file under `target/distributionx-testnet/` (`crates/distributionx-cli/src/commands.rs:694-703`). A keychain-backed alternative exists in `crates/distributionx-wallet-ref/src/storage.rs` (`KeychainSeedStore`) but is not the demo default. Under the active `claim_private` path the claimant CLI writes the salt and the rest of the witness into `claim.tx` so the in-program verifier can rebuild the journal at submit time; that file is read by the local submit adapter and forwarded into the LEZ transaction's instruction args. The salt is therefore present in `claim.tx`, in the relayer's claim payload, and in the chain transcript. A receipt-based `claim` path would not have this property but is not currently runnable, as covered in the Privacy Model section above.

**Secrecy boundary.** The distributor knows every salt because it built the CSV and bundle, so it can precompute a nullifier-to-row mapping. DistributionX protects observers, not the distributor. Per-recipient secrecy depends on the encrypted bundle row reaching only the intended recipient and the recipient's seed file staying protected against the local host. Compromising either reveals that recipient's salt.

**Public exposure.** The active `claim_private` path puts the salt in the transaction instruction args, so the chain transcript carries it (see Privacy Model above for the full witness list and the proposed follow-up fixes). Salts would not be in the Risc0 `claim` path's journal or instruction data, but that path is not currently runnable under the shielded flow.

## LEZ Account Model

The IDL in `crates/distributionx-program/idl/distributionx.json` defines `Airdrop` and `NullifierRecord` PDAs, plus `init_airdrop`, `fund`, `claim`, `claim_private`, and `close`. The active reviewer flow submits the `claim_private` instruction: the program verifies the witness in-program against the rebuilt journal, debits the vault, credits the nullifier PDA balance, and emits the local submit receipt. The local submit adapter then settles the configured custom token transfer to the destination commitment account.

The receipt-based `claim` instruction is defined in the program but is not used by the active flow. It would verify a Risc0 receipt without exposing the witness, but its `#[account(mut)] recipient` parameter requires an account that can be claimed by the program in the post-state, which a shielded one-time destination commitment cannot satisfy (see Privacy Model). Making `claim` runnable for shielded destinations is a tracked follow-up.

The relayer architecture is claimant-built: the claimant CLI or module computes the destination commitment and submits an opaque serialized LEZ transaction plus receipt or journal metadata. The relayer forwards the transaction and returns the testnet transaction id.

## Security Assumptions

SHA-256, strict Ed25519 verification, X25519 ECDH, HKDF-SHA-256, ChaCha20-Poly1305, Risc0 receipt soundness, and LEZ transaction atomicity are assumed secure. The local device and wallet seed storage are trusted.

## Threat Model And Residual Leakage

The main assets are eligibility-address privacy, per-recipient salt and Merkle path confidentiality, nullifier uniqueness, claim destination integrity, and distributor vault funds.

Public chain observers see the airdrop root, bucket id, nullifier, destination commitment, timing, and transaction metadata. Under the active `claim_private` path they also see the witness fields in the transaction instruction args (eligible address, salt, claim signature, Merkle path); see the Privacy Model section above for the breakdown and the tracked follow-ups. A receipt-based `claim` path would not expose the witness but is not currently runnable for shielded destinations. Observer unlinkability holds within each amount bucket under the bound documented in the Bucket Anonymity section above; it also assumes salts remain secret from observers under the receipt path (which is not the active path) and that claims avoid wallet-funded gas linkage.

Relayers see the full `claim.tx` payload, which under the active `claim_private` path includes the witness block (`private_claim`) alongside the receipt bytes, shielded destination metadata (`recipient_npk`, `recipient_vpk`), nullifier, destination commitment, and claim timing. The witness is therefore present at the relayer interface and in any file-system observer of `claim.tx`. Relayers can censor or delay a claim but cannot redirect it because the in-circuit signature binds the destination commitment. Other eligible recipients can claim only their own encrypted row unless they compromise another recipient's local key material.

The distributor knows the input CSV and may retain salts. That means the distributor can precompute nullifier-to-row mappings if it keeps the salt table; DistributionX protects observers from learning the claimant address, not from a distributor that preserves its original eligibility secrets. A compromised local host is out of scope.

Failed proof verification, insufficient vault balance, or failed token settlement must not be reported as a completed claim. The transaction path verifies the proof, debits the vault, and inserts the nullifier atomically; the local submit adapter waits for both the claim transaction and the custom-token settlement transaction before returning success.

## Integration

Run the standalone shielded path:

```bash
bash scripts/standalone-sequencer.sh restart --clean
bash scripts/e2e.sh private-localnet
```

That flow preserves the shielded destination packet, generates a real Risc0 receipt with `RISC0_DEV_MODE=0`, submits the LEZ `claim_private` transaction (the only path that currently runs end-to-end with shielded destinations; see Privacy Model), rejects a duplicate local claim, and closes the airdrop on-chain.
