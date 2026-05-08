# DistributionX Benchmark Report

## Host Measurements

| Benchmark | Result | Reproduce |
|---|---:|---|
| Bundle decrypt, 1k all-fail scan | 160.38-170.52 ms | `cargo bench -p distributionx-wallet-ref --bench bundle_decrypt_1k` |
| Host constraint verifier, strict Ed25519 plus Merkle path | 138.22-153.31 us | `cargo bench -p distributionx-circuit --bench strict_ed25519_cost` |
| Real Risc0 proof generation (release build) | 39-42 min wall on this CPU for the 30-claimant fixture | `RISC0_DEV_MODE=0 cargo run --release -p distributionx-cli -- prove ...` |
| Real Risc0 proof generation (debug build, **avoid**) | 40-60+ min on CPU under swap pressure | same command without `--release` — wrapper marshalling slows the prover by an order of magnitude |

## LEZ Sequencer Measurements

CU values for LP-0003 are captured per the brief by running an end-to-end demo against a LEZ sequencer in **standalone mode** (`scripts/standalone-sequencer.sh restart --clean`). The current LEZ RPC `getTransaction` response does not expose a receipt CU field, so the standalone helper instruments local LEZ Risc0 execution/proving cycle counts and writes them into the same receipt JSON files used by the table below. These values are local standalone LEZ cycle counters, not fields returned by public RPC receipts.

Most-recent successful evidence: see [`docs/run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-06.json`](../run-logs/deployment/standalone-lez-shielded-real-proof-2026-05-06.json). That run was captured from a clean standalone LEZ sequencer and reached `DISTRIBUTIONX_E2E_PASS`: `INIT_OK`, `FUND_OK`, `PROVE_LOCAL_OK` with `risc0_real_proof:OK`, `VERIFY_OK` with `risc0_receipt_verify:verified`, on-chain private `CLAIM_OK`, local `E_ALREADY_CLAIMED` double-claim rejection, and on-chain `CLOSE_OK`.

The CU table below is regenerated in place by `scripts/extract-cu.sh` from `target/distributionx-testnet/receipts/<op>.json` files. `scripts/local-submit.sh` writes these receipt files automatically for `init`, `fund`, `claim`, and `close`. For manually captured receipts, keep the same schema:

```json
{ "tx_id": "<hex>", "status": "OK|ERROR", "cu": <integer> }
```

The private claim row reports the outer privacy circuit cycle count. The same receipt also records `private_program_cu = 5174193`, the inner private DistributionX program proof cycle count. Keep the raw receipt JSON files with the final submission so the CU field path is auditable.

<!-- BEGIN cu-table -->
| Operation | Tx id | Receipt file | Status | CU |
|---|---|---|---|---:|
| `init_airdrop` on standalone LEZ | 9bb3264494e75daf6f6d5fd1b3c476d683d217ffada18088b166c5c9d2138d13 | `target/distributionx-testnet/receipts/init_airdrop.json` | OK | 444366 |
| `fund` on standalone LEZ | bc6bc61e430aa90c8ec683f5f154ddc72db005d2b3590945955e2b73787c956a | `target/distributionx-testnet/receipts/fund.json` | OK | 448211 |
| `claim` on standalone LEZ | 286b12208328c8d7e48b868e83cc3e1745a09622d392445679dade3a8e137a76 | `target/distributionx-testnet/receipts/claim.json` | OK | 786876 |
| `close` on standalone LEZ | fc51f3135f02d77027fe2d36beb65486ff0e562397c773fc99669dcbf0240ceb | `target/distributionx-testnet/receipts/close.json` | OK | 505564 |
<!-- END cu-table -->
