<p align="center">
  <img src="basecamp-app/icons/icon.png" alt="DistributionX logo" width="152">
</p>

<h1 align="center">DistributionX</h1>

<p align="center">
  Private allowlist distributions for the Logos Execution Zone.
</p>

<p align="center">
  <a href="https://github.com/Timidan/dist-x/actions/workflows/distributionx-ci.yml"><img src="https://github.com/Timidan/dist-x/actions/workflows/distributionx-ci.yml/badge.svg?branch=master" alt="CI status"></a>
  <a href="https://github.com/Timidan/dist-x/releases/tag/v0.1.0">Release v0.1.0</a>
  ·
  <a href="LICENSE-MIT">MIT</a> or <a href="LICENSE-APACHE">Apache-2.0</a>
</p>

DistributionX lets a distributor fund an allowlist without publishing recipient
addresses. Each recipient proves eligibility through Logos Execution Zone (LEZ)
privacy-preserving execution. The public state records the payout and nullifier,
not the private membership witness.

## How it works

1. The distributor creates an eligibility list and an encrypted claim bundle.
2. The LEZ program stores a Merkle root and funds the distribution vault.
3. A recipient proves one eligible row and submits `claim_ppe` through LEZ.
4. The program pays the recipient and records a nullifier in one transaction.

The private witness contains the eligible address, salt, signature, and Merkle
path. These values do not appear in the public `claim_ppe` transaction message.
The distributor still knows the original eligibility list. See the
[privacy and threat model](docs/WRITEUP.md) for the full trust boundary.

## Verified testnet result

| Item | Result |
|---|---|
| Network | LEZ public testnet, compatible with the pinned LEZ v0.2.4 source |
| Program ID | `4bf08c88a91871ecf69ff08af42591a597c51142cbc1f9c6fbbb7d2e888d9ee3` |
| Deployment | [Transaction `2186…6181`](https://explorer.testnet.lez.logos.co/transaction/2186b9ba9e95e4926f2800e88b5d0653bda3d1669414f0a19c6daf0798576181), block 8138 |
| Completed run | 2 native distributions and 20 included `claim_ppe` transactions |
| Proof mode | `RISC0_DEV_MODE=0` with `claim_ppe` |
| Release source | [`v0.1.0`](https://github.com/Timidan/dist-x/releases/tag/v0.1.0), commit `74f81ab9` |

Review the [transaction report](docs/TESTNET_EVIDENCE.md), the
[public manifest](docs/testnet-evidence/v0.1.0/manifest.json), and all
[27 captured responses](docs/testnet-evidence/v0.1.0/rpc). The structured
evidence contains no wallet seed, private witness, serialized claim, or private
receipt.

## Run the project

Use the Basecamp app for the visual reviewer flow:

```bash
bash scripts/start-basecamp.sh --reset-localnet --clean-user-dir
```

Run the full command-line lifecycle with real proofs:

```bash
bash scripts/e2e.sh ci-localnet
```

Build and verify both Logos package files:

```bash
bash scripts/package.sh
```

The package command creates:

| Package | Contents |
|---|---|
| `distributionx-client.lgx` | The Logos core module and DistributionX command-line client |
| `DistributionX-ui.lgx` | The Basecamp user interface |
| `SHA256SUMS` | Checksums for both package files |

You can also download these files from the
[v0.1.0 release](https://github.com/Timidan/dist-x/releases/tag/v0.1.0).

## Check the project

Run the fast local checks before each commit:

```bash
bash scripts/ci-local.sh quick
```

Run the complete local continuous integration (CI) suite before a release:

```bash
bash scripts/ci-local.sh all
```

GitHub Actions also builds the Rust workspace, checks the Logos modules, loads
the exact package files, checks the Basecamp interface, and runs the real-proof
LEZ lifecycle.

## Capture public testnet evidence

The evidence tool separates preparation from the two approved write phases.
Preparation sends no transaction. Keep custom-token settlement disabled for the
native evidence flow.

```bash
unset DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT
bash scripts/testnet-evidence.sh prepare
quote_sha="$(<"target/testnet-evidence/${DISTRIBUTIONX_EVIDENCE_RUN_ID}/private/quote.sha256")"
bash scripts/testnet-evidence.sh smoke "${quote_sha}"
bash scripts/testnet-evidence.sh finish "${quote_sha}"
bash scripts/testnet-evidence.sh verify
```

Approve the quote before `smoke`. Review the canary result before `finish`.
The publishable output is only the `public/` directory for that run. Never
publish its sibling `private/` directory.

## Project map

| Path | Purpose |
|---|---|
| `crates/distributionx-program/` | LEZ program and deterministic error codes |
| `methods/` | Risc0 guest program and proof methods |
| `crates/distributionx-client/` | Rust client library |
| `crates/distributionx-cli/` | Command-line client |
| `distributionx_client_module/` | Logos core module |
| `basecamp-app/` | Basecamp application and interface tests |
| `idl/` | SPEL interface definition |

## Documentation

- [System architecture](DistributionX.system-architecture.excalidraw)
- [Privacy and threat model](docs/WRITEUP.md)
- [Public testnet evidence](docs/TESTNET_EVIDENCE.md)
- [Proof time and LEZ operation costs](docs/bench/REPORT.md)

## License

DistributionX is available under the MIT or Apache-2.0 license.
