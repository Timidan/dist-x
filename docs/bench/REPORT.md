# DistributionX Benchmark Report

## Host Measurements

| Benchmark | Result | Reproduce |
|---|---:|---|
| Bundle decrypt, 1k all-fail scan | 160.38-170.52 ms | `cargo bench -p distributionx-wallet-ref --bench bundle_decrypt_1k` |
| Host constraint verifier, strict Ed25519 plus Merkle path | 138.22-153.31 us | `cargo bench -p distributionx-circuit --bench strict_ed25519_cost` |
| Real Risc0 proof generation (release build) | 39-42 min wall on this CPU for the 30-claimant fixture | `RISC0_DEV_MODE=0 cargo run --release -p distributionx-cli -- prove ...` |
| Real Risc0 proof generation (debug build, **avoid**) | 40-60+ min on CPU under swap pressure | same command without `--release` — wrapper marshalling slows the prover by an order of magnitude |

## LEZ Sequencer Measurements

### rc5 PPE testnet (historical snapshot)

The prior LP-0003 evidence run was captured on `https://testnet.lez.logos.co` when it ran LEZ v0.2.0-rc5. The full transaction list and capture-time `getTransaction` responses are in [docs/TESTNET_EVIDENCE.md](../TESTNET_EVIDENCE.md): fixed program id `218a07eb268df922ded961fefd7d035752b44d05f4bb5172305fb0bc54506989`, **2 distributions**, **20 `claim_ppe` claims**, and 20 token settlements. The testnet was later reset and sampled IDs now return `result: null`; fresh v0.2.4-compatible public evidence and current CU observations are still required.

`claim_ppe` runs the witness verification through privacy-preserving execution (PPE): the heavy proof is composed client-side and the sequencer verifies a single succinct receipt, so the on-chain claim's public-execution cost stays far under the 32M public-execution cap. The public-execution CU is identical across all 20 claims.

| Operation | CU (public execution) | Source |
|---|---:|---|
| `init_airdrop` | 442721 | standalone reproduction (cycle count is deterministic per program) |
| `fund` | 447195 | standalone reproduction |
| `claim_ppe` (each of 20 claims) | 504401 | archived rc5 evidence receipts (`docs/testnet-evidence/{b1,c1}/receipts/*.json`) |

The testnet RPC `getTransaction` response did not expose a CU field; the values above came from the local LEZ public-execution cycle counter written alongside each capture-time claim. They remain historical measurements for the rc5 program image and must not be presented as current v0.2.4 observations.

### Standalone LEZ (pre-rc5, historical)

Earlier CU values were captured against a standalone LEZ sequencer on the pre-rc5 receipt-based `claim` path. The tracked [`standalone-lez-shielded-real-proof-2026-05-06.json`](../run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-06.json) snapshot is retained only as historical context.

<!-- BEGIN cu-table -->
| Operation | Tx id | Receipt file | Status | CU |
|---|---|---|---|---:|
| `init_airdrop` on standalone LEZ | pending | `target/distributionx-testnet/receipts/init_airdrop.json` | pending | pending |
| `fund` on standalone LEZ | pending | `target/distributionx-testnet/receipts/fund.json` | pending | pending |
| `claim` on standalone LEZ | pending | `target/distributionx-testnet/receipts/claim.json` | pending | pending |
| `close` on standalone LEZ | pending | `target/distributionx-testnet/receipts/close.json` | pending | pending |
<!-- END cu-table -->
