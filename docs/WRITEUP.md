# DistributionX Write-Up

> **Current path.** The repository pins LEZ v0.2.4 and ships `claim_ppe` through LEZ privacy-preserving execution (PPE). Witness privacy comes from the PPE transaction format: instruction data and witness fields are not present in the public transaction message. The receipt-based public `claim` instruction remains in the program but exceeds the public-execution budget for this circuit; `claim_private` remains an opt-in, witness-revealing diagnostic fallback. The previous two-distribution rc5 testnet run is an archived snapshot whose transaction IDs no longer resolve after a testnet reset; see [TESTNET_EVIDENCE.md](TESTNET_EVIDENCE.md).

## Commitment Scheme

DistributionX parses an eligibility CSV into amount buckets and computes `leaf = H_LEAF(address, bucket_id, salt)` for each row. The on-chain commitment is the fixed-depth Merkle root. The bucket table is hashed separately and bound into the airdrop id and encrypted bundle associated data.

## Claim Uniqueness Scope

On-chain enforcement is per nullifier rather than per recipient. Each claim publishes `nullifier = H_NULL(salt) = SHA256("logos-distributionx/null-v1" || salt)` (`crates/distributionx-tree/src/hash.rs:26-31`). The nullifier binds to the salt only, not to the address. The LEZ/SPEL account model stores a `NullifierRecord` at PDA seed `["nullifier", airdrop_id, nullifier]` (`methods/guest/src/bin/distributionx.rs:381, 472`), and a second initialization with the same seeds returns `E_ALREADY_CLAIMED` (`methods/guest/src/bin/distributionx.rs:390-394`).

The committed Merkle leaf binds `(address, bucket_id, salt)` together (`crates/distributionx-tree/src/hash.rs:3-10`), so a valid claim corresponds to exactly one committed row in the tree.

Address-level uniqueness is enforced at the CSV ingest stage, not by the on-chain program. The parser in `crates/distributionx-tree/src/csv.rs:25-33` uses a `HashSet<address>` to reject duplicate addresses with `CliDuplicateAddr` before the tree is built. If a distributor bypassed `parse_csv` and constructed leaves directly with the same address under two different salts, the on-chain program would honor both claims because the two rows would have two different nullifiers.

The accurate reading of "each recipient can claim once" is therefore: on the chain, once per committed leaf which is once per nullifier; in practice, once per address, with the CSV dedup as the load-bearing piece for the recipient-level reading.

## Privacy Model

The targeted privacy property is that on-chain observers should not learn the eligible address, row salt, claim signature, or Merkle path from a valid claim transcript. The shipping instruction is `claim_ppe`; the two public alternatives below are retained for compatibility and diagnostics.

**`claim_ppe` (shipping path).** The CLI command is still named `distributionx-cli claim`, but its default submit adapter constructs the `claim_ppe` instruction and passes the witness locally to `send_privacy_preserving_tx`. The resulting public PPE message carries no instruction data. The IDL marks this instruction `public: false, private_owned: true`, so the generic generated Rust and C clients deliberately omit a public submission function; the PPE adapter is the supported submission path. The instruction validates the committed row, creates the nullifier record, debits the program vault, and credits the private recipient atomically. `prove` also generates and locally verifies a real Risc0 Groth16 receipt with `RISC0_DEV_MODE=0`; `claim_ppe` does not put that receipt in its instruction arguments.

**`claim` (legacy receipt path).** This public instruction accepts `airdrop_id`, `nullifier`, `receipt_bytes`, and `now_unix`, verifies the Groth16 receipt, and reads its public journal. It preserves witness privacy, but the receipt verifier is too expensive for the current public-execution budget and is not the reviewer flow.

**`claim_private` (in-program verifier, opt-in fallback).** This instruction runs witness verification inside the program, so `claimant_address`, `salt`, `claim_sig`, `merkle_siblings`, and `merkle_path_is_right` are public instruction arguments. It is gated behind `DISTRIBUTIONX_USE_CLAIM_PRIVATE=1` and is not the demo default. It is retained only for operators who accept that loss of observer privacy.

**A note on naming.** The `claim_private` identifier predates this audit and is misleading in its current form. The instruction is the opt-in in-program verifier described above and does not provide observer privacy for the witness under its current submission path. A clearer identifier would be something like `claim_inline` (because the verifier runs inline in the LEZ program rather than inside the zkVM). The rename is deferred because it touches the LEZ program, all three IDL mirrors, the generated client and FFI, scripts, tests, and several doc sections (about 17 files in total). The documentation above describes what the instruction actually does.

The claim signature binds `logos-distributionx/claim-v2 || airdrop_id || claim_destination_commitment` (`crates/distributionx-wallet-ref/src/sign.rs:1-7`). A relayer or observer can resubmit the same proof to the same commitment, but changing the destination commitment invalidates the in-circuit Ed25519 verification.

## Bucket Anonymity

The `bucket_id` is public. It appears in the Risc0 journal (`crates/distributionx-circuit/src/journal.rs:7`) and as an explicit arg to `claim_private`. The `bucket_table` (the amount schedule) is public init data submitted with `init_airdrop` (`idl/distributionx.idl.json:61-62`).

Observer unlinkability is therefore bounded by the per-bucket anonymity set size. The probability that a given on-chain claim corresponds to a particular eligible recipient is at most 1/k per bucket, where k is the recipient count for that bucket. Two failure modes follow directly:

- A singleton bucket (k=1) reveals the recipient by amount. The observer learns exactly which eligibility row claimed.
- A small bucket (k=2 or k=3) shrinks the anonymity set sharply. Repeated claims, correlated timing, or out-of-band metadata can push the observer toward a single candidate.

The CLI surfaces this risk during CSV ingest. `inspect-csv` emits a warning when the smallest bucket has fewer than 8 recipients (`crates/distributionx-cli/src/commands.rs:1110-1114`), and the `pad-csv --min-per-bucket N` command lets a distributor top up small buckets to a desired baseline. The CSV parser also caps the table at 32 buckets and 50,000 recipients (`crates/distributionx-tree/src/csv.rs:40-50`).

The on-chain program does not enforce a minimum k at `init_airdrop`. Bucket anonymity is an accepted residual leakage; the distributor is trusted to choose a bucket schedule that fits the privacy budget they want for their list.

## Salt Threat Model

**Generation.** Salts are 32 bytes per row drawn from the OS CSPRNG via `OsRng.fill_bytes` (`crates/distributionx-tree/src/bundle.rs:44-48`). The bundle builder rejects same-bundle collisions before producing the leaf. The entropy assumption is that `rand::rngs::OsRng` (backed by getrandom on Linux and macOS) is unbroken.

**Distribution.** Each row is sealed for its intended recipient. The row plaintext `{address, bucket_id, salt, merkle_path}` is encrypted with ChaCha20-Poly1305 AEAD; the key and nonce come from X25519 ECDH against the recipient's claim key (the recipient's ed25519 pubkey converted to x25519 via libsodium), passed through HKDF-SHA-256 with bundle context binding (`crates/distributionx-tree/src/bundle.rs:68-105`). Only the intended recipient's claim key can decrypt their row.

**Storage.** The reviewer flow stores the wallet seed under the ignored `target/` state directory. A keychain-backed alternative exists in `crates/distributionx-wallet-ref/src/storage.rs` but is not the demo default. The current `claim.tx` is a private local prover artifact and contains the `private_claim` witness needed for PPE submission; it must never be uploaded or committed. Privacy is provided by the submitted PPE message, not by treating `claim.tx` as public evidence.

**Secrecy boundary.** The distributor knows every salt because it built the CSV and bundle, so it can precompute a nullifier-to-row mapping. DistributionX protects observers, not the distributor. Per-recipient secrecy depends on the encrypted bundle row reaching only the intended recipient and the recipient's seed file staying protected against the local host. Compromising either reveals that recipient's salt.

**Public exposure.** Salts are not present in the Risc0 journal or the public PPE transaction message. Under the `claim_private` opt-in the salt is part of the public instruction args; the default demo does not use that path.

## LEZ Account Model

The IDL in `crates/distributionx-program/idl/distributionx.json` defines `Airdrop` and `NullifierRecord` PDAs plus `init_airdrop`, `fund`, `claim`, `claim_ppe`, `claim_private`, and `close`. The reviewer flow submits `claim_ppe`: LEZ PPE proves the private instruction inputs, while the program atomically validates the claim, records the nullifier, debits the vault, and credits the private recipient. Optional custom-token settlement is a later, separate token-program transaction and is not part of the minimal compatibility smoke.

The `claim_private` instruction remains an opt-in fallback that runs the witness check inside the program. It is enabled via `DISTRIBUTIONX_USE_CLAIM_PRIVATE=1`; it is not the demo default and does not provide observer privacy for the witness under public submission.

The relayer architecture is claimant-built: the claimant CLI or module computes the destination commitment and submits an opaque serialized LEZ transaction plus receipt or journal metadata. The relayer forwards the transaction and returns the testnet transaction id.

## Security Assumptions

SHA-256, strict Ed25519 verification, X25519 ECDH, HKDF-SHA-256, ChaCha20-Poly1305, Risc0 receipt soundness, and LEZ transaction atomicity are assumed secure. The local device and wallet seed storage are trusted.

## Threat Model And Residual Leakage

The main assets are eligibility-address privacy, per-recipient salt and Merkle path confidentiality, nullifier uniqueness, claim destination integrity, and distributor vault funds.

Public chain observers see the airdrop root, bucket id, nullifier, destination commitment, timing, and transaction metadata. Under `claim_ppe` they should not learn the eligible address, salt, Merkle path, claim signature, or private destination keys from the public transaction. Observer unlinkability holds within each amount bucket under the bound documented above; it also assumes salts remain secret and claims avoid wallet-funded gas linkage.

The default local adapter receives the private witness and shielded destination metadata before it constructs the PPE transaction. Therefore the adapter host and `claim.tx` storage are inside the trusted boundary and must not be treated as a privacy-preserving relayer API. The public sequencer message does not expose those fields. A relayer can censor or delay a claim but cannot redirect it because the signature binds the destination commitment.

The distributor knows the input CSV and may retain salts. That means the distributor can precompute nullifier-to-row mappings if it keeps the salt table; DistributionX protects observers from learning the claimant address, not from a distributor that preserves its original eligibility secrets. A compromised local host is out of scope.

Failed proof verification or insufficient vault balance must not be reported as a completed claim. The native payout and nullifier insertion are atomic within `claim_ppe`. Optional custom-token settlement is not atomic with the DistributionX claim; the adapter preflights it and reports it separately when enabled.

## Integration

Run the standalone shielded path:

```bash
bash scripts/e2e.sh ci-localnet
```

That flow generates and verifies a real Risc0 receipt with `RISC0_DEV_MODE=0`, submits the LEZ `claim_ppe` transaction, rejects a duplicate from local nullifier state, and closes the airdrop on-chain. It does not claim that the duplicate attempt was rebroadcast or rejected by the sequencer.
