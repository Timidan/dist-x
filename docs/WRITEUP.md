# DistributionX Write-Up

## Commitment Scheme

DistributionX parses an eligibility CSV into amount buckets and computes `leaf = H_LEAF(address, bucket_id, salt)` for each row. The on-chain commitment is the fixed-depth Merkle root. The bucket table is hashed separately and bound into the airdrop id and encrypted bundle associated data.

## Claim Uniqueness

Each claim publishes `nullifier = H_NULL(salt)`. The LEZ/SPEL account model stores a `NullifierRecord` at PDA seed `["nullifier", "airdrop_id", "nullifier"]`; a second initialization returns `E_ALREADY_CLAIMED`.

## Privacy Model

The private witness contains the eligible address, salt, claim signature, and Merkle path. The public journal contains only `airdrop_id`, `merkle_root`, `bucket_id`, `nullifier`, and `claim_destination_commitment`. The public receipt claim instruction accepts `airdrop_id`, `nullifier`, `receipt_bytes`, and `now_unix`; on that path the eligible address, salt, signature, and Merkle path stay inside the locally generated Risc0 receipt witness. The LEZ-private `claim_private` path carries the same witness fields inside the private transaction instruction so LEZ can verify eligibility without nesting the Risc0 verifier in the public session; those fields are private-execution inputs, not public claim journal data.

The claim signature binds `logos-distributionx/claim-v2 || airdrop_id || claim_destination_commitment`. A relayer or observer can submit the same proof to the same commitment, but changing the destination commitment invalidates the in-circuit Ed25519 verification.

## LEZ Account Model

The IDL in `crates/distributionx-program/idl/distributionx.json` defines `Airdrop` and `NullifierRecord` PDAs, plus `init_airdrop`, `fund`, `claim`, `claim_private`, and `close`. The public `claim` path verifies the Risc0 receipt against the DistributionX image id, verifies the receipt journal against airdrop state, checks the recipient account matches `claim_destination_commitment`, debits the vault, credits the initialized recipient account, and writes the nullifier atomically. The LEZ-private `claim_private` path builds the same journal from private instruction inputs and verifies the witness directly inside the private transaction.

The relayer architecture is claimant-built: the claimant CLI/module computes the destination commitment and submits an opaque serialized LEZ transaction plus receipt/journal metadata. The relayer forwards the transaction and returns the testnet transaction id.

## Security Assumptions

SHA-256, strict Ed25519 verification, X25519 ECDH, HKDF-SHA-256, ChaCha20-Poly1305, Risc0 receipt soundness, and LEZ transaction atomicity are assumed secure. The local device and wallet seed storage are trusted.

## Threat Model And Residual Leakage

The main assets are eligibility-address privacy, per-recipient salt and Merkle path confidentiality, nullifier uniqueness, claim destination integrity, and distributor vault funds.

Public chain observers see the airdrop root, bucket id, nullifier, destination commitment, timing, and transaction metadata. They should not learn the eligible address, salt, Merkle path, claim signature, or destination wallet/account id from a valid proof transcript. Observer unlinkability holds within each amount bucket when salts remain secret from observers and claims avoid wallet-funded gas linkage.

Relayers see claim payload timing, destination commitment, nullifier, and receipt bytes. They can censor or delay a claim, but cannot redirect it because the in-circuit signature binds the destination commitment. Other eligible recipients can claim only their own encrypted row unless they compromise another recipient's local key material.

The distributor knows the input CSV and may retain salts. That means the distributor can precompute nullifier-to-row mappings if it keeps the salt table; DistributionX protects observers from learning the claimant address, not from a distributor that preserves its original eligibility secrets. A compromised local host is out of scope.

Failed proof verification, insufficient vault balance, or failed recipient credit must not persist a nullifier. The production transaction path is designed to verify the proof, debit the vault, credit the destination, and insert the nullifier atomically.

## Integration

Run the standalone shielded path:

```bash
bash scripts/standalone-sequencer.sh restart --clean
bash scripts/e2e.sh private-localnet
```

That flow preserves the shielded destination packet, generates a real Risc0 receipt with `RISC0_DEV_MODE=0`, submits the LEZ `claim_private` transaction, rejects a duplicate local claim, and closes the airdrop on-chain.
