# DistributionX Benchmark Report

## Host Measurements

| Benchmark | Result | Reproduce |
|---|---:|---|
| Bundle decrypt, 1k all-fail scan | 160.38-170.52 ms | `cargo bench -p distributionx-wallet-ref --bench bundle_decrypt_1k` |
| Host constraint verifier, strict Ed25519 plus Merkle path | 138.22-153.31 us | `cargo bench -p distributionx-circuit --bench strict_ed25519_cost` |
| Real Risc0 eligibility proof, current reviewer fixture | **19 min 20 sec** wall on this CPU | canonical v0.2.4 lifecycle with `RISC0_DEV_MODE=0` |
| Real Risc0 claim PPE composition, current reviewer fixture | **26 min 12 sec** wall on this CPU | exact-prestate v0.2.4 replay with `RISC0_DEV_MODE=0` |
| Real Risc0 proof generation (release build) | 39-42 min wall on this CPU for the 30-claimant fixture | `RISC0_DEV_MODE=0 cargo run --release -p distributionx-cli -- prove ...` |
| Real Risc0 proof generation (debug build, **avoid**) | 40-60+ min on CPU under swap pressure | same command without `--release` — wrapper marshalling slows the prover by an order of magnitude |

## LEZ Sequencer Measurements

### LEZ v0.2.4 standalone (current)

The canonical lifecycle passed against LEZ v0.2.4 (`47eba256479f6f785acbd138834340703cd03401`) with `RISC0_DEV_MODE=0`: deploy, initialize, fund, generate and verify the real eligibility proof, compose and submit the real PPE claim, reject a duplicate claim, and close. The fixed program id was `4bf08c88a91871ecf69ff08af42591a597c51142cbc1f9c6fbbb7d2e888d9ee3`.

Public-operation CU is the sequencer's last `user cycles` counter before that exact transaction's validation marker. `claim_ppe` is different: its value is the deterministic Risc0 guest execution reported by `SessionInfo::cycles` for the exact funded pre-state and claim inputs. That measurement-only execution submitted no transaction; the separately listed real claim transaction was successfully proved and committed with `RISC0_DEV_MODE=0`. The public testnet RPC does not expose a separate proof-verification CU field.

<!-- BEGIN cu-table -->
| Operation | CU | Evidence |
|---|---:|---|
| `init_airdrop` | **442994** | tx `60971c410fd5cafee3ce2af5c06ca5aac24ec5481532211c47e4064e57fd88fe`, block 18 |
| `fund` | **447471** | tx `ff6b59c5d383f933d26c547df6898a40a82f19ff3927208f0264c292d1c0a619`, block 21 |
| `claim_ppe` | **5154242** | exact-prestate guest execution; real tx `8fff0c212bacabd6ee60e1535cd8ad5e23ccfb9fd1efdb1744935cbeed9904da`, block 320 |
| `close` | **504505** | tx `fe431ec41f65ac71248401db86c84aad7c9fab8eac3ddc5f5b9f0c8a4b96e49c`, block 597 |
<!-- END cu-table -->

The machine-readable capture is [`lez-v0.2.4-cu.json`](./lez-v0.2.4-cu.json). These are local standalone-chain measurements, not public-testnet transaction claims.

### Current v0.1.0 public testnet

The current public evidence run executed release `v0.1.0` with `RISC0_DEV_MODE=0` against the healthy LEZ testnet endpoint whose built-ins matched pinned v0.2.4 commit `47eba256479f6f785acbd138834340703cd03401`. It deployed program `4bf08c88a91871ecf69ff08af42591a597c51142cbc1f9c6fbbb7d2e888d9ee3`, initialized and funded two native-token distributions, and included 20 distinct `claim_ppe` transactions in 27 approved writes. The [readable transaction report](../TESTNET_EVIDENCE.md), [manifest](../testnet-evidence/v0.1.0/manifest.json), and 27 capture-time RPC responses are committed.

The public RPC proves transaction inclusion but does not expose per-operation CU. Do not substitute the standalone CU table above as a public-testnet measurement; it is the exact pinned-runtime reproduction used to answer the separate cost requirement.

### rc5 PPE testnet (historical snapshot)

The prior LP-0003 evidence run was captured on `https://testnet.lez.logos.co` when it ran LEZ v0.2.0-rc5. Its archived section in [docs/TESTNET_EVIDENCE.md](../TESTNET_EVIDENCE.md) records fixed program id `218a07eb268df922ded961fefd7d035752b44d05f4bb5172305fb0bc54506989`, **2 distributions**, **20 `claim_ppe` claims**, and 20 token settlements. The testnet was later reset and sampled IDs now return `result: null`; use the current `v0.1.0` section above for submission evidence.

`claim_ppe` runs the witness verification through privacy-preserving execution (PPE): the heavy proof is composed client-side and the sequencer verifies a single succinct receipt, so the on-chain claim's public-execution cost stays far under the 32M public-execution cap. The public-execution CU is identical across all 20 claims.

| Operation | CU (public execution) | Source |
|---|---:|---|
| `init_airdrop` | 442721 | standalone reproduction (cycle count is deterministic per program) |
| `fund` | 447195 | standalone reproduction |
| `claim_ppe` (each of 20 claims) | 504401 | archived rc5 evidence receipts (`docs/testnet-evidence/{b1,c1}/receipts/*.json`) |

The testnet RPC `getTransaction` response did not expose a CU field; the values above came from the local LEZ public-execution cycle counter written alongside each capture-time claim. They remain historical measurements for the rc5 program image and must not be presented as current v0.2.4 observations.

### Standalone LEZ (pre-rc5, historical)

Earlier CU values were captured against a standalone LEZ sequencer on the pre-rc5 receipt-based `claim` path. The tracked [`standalone-lez-shielded-real-proof-2026-05-06.json`](../run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-06.json) snapshot is retained only as historical context.
