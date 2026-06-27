# DistributionX Benchmark Report

## Host Measurements

| Benchmark | Result | Reproduce |
|---|---:|---|
| Bundle decrypt, 1k all-fail scan | 160.38-170.52 ms | `cargo bench -p distributionx-wallet-ref --bench bundle_decrypt_1k` |
| Host constraint verifier, strict Ed25519 plus Merkle path | 138.22-153.31 us | `cargo bench -p distributionx-circuit --bench strict_ed25519_cost` |
| Real Risc0 proof generation (release build) | 39-42 min wall on this CPU for the 30-claimant fixture | `RISC0_DEV_MODE=0 cargo run --release -p distributionx-cli -- prove ...` |
| Real Risc0 proof generation (debug build, **avoid**) | 40-60+ min on CPU under swap pressure | same command without `--release` — wrapper marshalling slows the prover by an order of magnitude |

## LEZ Sequencer Measurements

### rc5 PPE testnet (live) — primary LP-0003 evidence

The LP-0003 evidence run is recorded on the **live LEZ testnet** (`https://testnet.lez.logos.co`, LEZ v0.2.0-rc5). The full transaction list and per-tx `getTransaction` verification are in [docs/TESTNET_EVIDENCE.md](../TESTNET_EVIDENCE.md): fixed program id `218a07eb268df922ded961fefd7d035752b44d05f4bb5172305fb0bc54506989`, **2 distributions** (`lp0003-rc5-b1`, `lp0003-rc5-c1`), **20 witness-private `claim_ppe` claims** plus 20 token settlements, all confirmed on-chain.

`claim_ppe` runs the witness verification through privacy-preserving execution (PPE): the heavy proof is composed client-side and the sequencer verifies a single succinct receipt, so the on-chain claim's public-execution cost stays far under the 32M public-execution cap. The public-execution CU is identical across all 20 claims.

| Operation | CU (public execution) | Source |
|---|---:|---|
| `init_airdrop` | 442721 | standalone reproduction (cycle count is deterministic per program) |
| `fund` | 447195 | standalone reproduction |
| `claim_ppe` (each of 20 claims) | 504401 | live testnet evidence receipts (`target/distributionx-testnet-rc5-evidence*/evidence/receipts/*.json`) |

The testnet RPC `getTransaction` response does not expose a CU field; the per-claim CU above is the local LEZ public-execution cycle counter written into the receipt JSON alongside each claim. Cycle counts are deterministic for a given program image, so the standalone `init`/`fund` counts equal the testnet ones. The `close` instruction is not part of the 20-claim evidence batch (distributions are left open during the run); its standalone CU is in the historical table below.

### Standalone LEZ (pre-rc5, historical)

Earlier CU values were captured against a LEZ sequencer in standalone mode (`scripts/standalone-sequencer.sh restart --clean`) on the pre-rc5 receipt-based `claim` path, before the testnet was redeployed to v0.2.0-rc5 and the claim path moved to PPE (`claim_ppe`). Preserved as historical context: [`docs/run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-13.json`](../run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-13.json) (refactored `claim` path) and [`docs/run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-06.json`](../run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-06.json) (`claim_private` opt-in fallback).

<!-- BEGIN cu-table -->
| Operation | Tx id | Status | CU |
|---|---|---|---:|
| `init_airdrop` (lp0003-rc5-b1, testnet) | f27918090fd3c6652b3d877eca004048718c4b95502b6c8f73edc6f2f3c833de | OK | 442721 |
| `fund` (lp0003-rc5-b1, testnet) | 46783c7b914cf3d4428c1958864acee70cc440925b91e0aa418b0e4d7dc48814 | OK | 447195 |
| `claim_ppe` (lp0003-rc5-b1 claim 01, testnet) | 18632790129b7045ac5e08f23859d03a2a0007f03a7b835281920fff719bed23 | OK | 504401 |
| `claim_ppe` (lp0003-rc5-c1 claim 01, testnet) | 5452afe34dd73569d5ade83fe18b557dfb88a2277c7f38bfe7add985857913e2 | OK | 504401 |
<!-- END cu-table -->
