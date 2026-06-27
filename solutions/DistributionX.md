# DistributionX FURPS Self-Assessment

## Functionality

The repository implements eligibility bundle construction, encrypted row decrypt, real Risc0 receipt generation, receipt verification, nullifier handling, expanded IDL artifacts, a CLI, configurable LEZ deployment/submit adapters, a Logos universal client module, and a Basecamp QML app.

## Usability

The README documents the required standalone LEZ environment, optional self-hosted testnet stack, deploy flow, CLI flow, Basecamp build, and verification commands. The CLI fails closed unless a real Risc0 receipt verifies and claim submission returns a LEZ transaction id.

## Reliability

Rust crates pass locally. The demo scripts require real deploy and submit adapters and do not fabricate program ids, proofs, or transaction ids.

## Performance

Host cryptographic benchmarks, real Risc0 proof timing, and standalone LEZ operation cycle/CU measurements are recorded in `docs/bench/REPORT.md`. The latest standalone evidence includes init, fund, shielded private claim, and close transaction hashes plus CU values.

## Supportability

The repository is dual-licensed MIT/Apache-2.0. The public docs surface is limited to the README, technical write-up, benchmark report, FURPS self-assessment, and filed upstream issue links.

## Filed Upstream Issues

- logos-blockchain/logos-execution-zone#467: https://github.com/logos-blockchain/logos-execution-zone/issues/467
- logos-co/scaffold#101: https://github.com/logos-co/scaffold/issues/101
- logos-blockchain/logos-blockchain#2691: https://github.com/logos-blockchain/logos-blockchain/issues/2691
- logos-co/logos-view-module-runtime#7: https://github.com/logos-co/logos-view-module-runtime/issues/7
