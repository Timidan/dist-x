# DistributionX

DistributionX is a private allowlist airdrop for the Logos Execution Zone (LEZ). A distributor publishes only a Merkle root on-chain. A claimant proves membership and claims to a private destination through the `claim_ppe` instruction, submitted via LEZ privacy-preserving execution (PPE). The witness fields (eligible address, salt, signature, Merkle path) are local PPE inputs and do not appear in the public transaction message. The repository is pinned to LEZ v0.2.4; the current public endpoint has a v0.2.2-v0.2.4-compatible built-in fingerprint, but exposes no exact server revision.

Architecture diagram: [DistributionX.system-architecture.excalidraw](DistributionX.system-architecture.excalidraw).

## Bounty Coverage

| Requirement | Evidence |
|---|---|
| LEZ program in Rust/SPEL | `crates/distributionx-program/`, `methods/guest/src/bin/distributionx.rs` |
| SPEL IDL | `idl/distributionx.idl.json`, `crates/distributionx-program/idl/distributionx.json` |
| Risc0 proof stack | `methods/`, `crates/distributionx-circuit/`, `distributionx-cli prove` |
| Eligibility committed without public addresses | `init_airdrop` stores `merkle_root` and `bucket_table_hash`; encrypted rows stay in `bundle.json` |
| Recipient claims without revealing eligible address | `claim_ppe` via PPE (`send_privacy_preserving_tx`); the public PPE message carries no instruction data/witness. Its IDL execution mode removes it from generated public-submit APIs, and program/client-generator tests cover the boundary. |
| LEZ testnet deployment (>=2 distributions, >=20 claims) | The prior rc5 batch is archived in [docs/TESTNET_EVIDENCE.md](docs/TESTNET_EVIDENCE.md); a fresh current-network batch is required before resubmission. |
| One claim per recipient | Nullifier PDA and `E_ALREADY_CLAIMED`; tests in `crates/distributionx-program/tests/` |
| Threat model and privacy model | [docs/WRITEUP.md](docs/WRITEUP.md) |
| Client SDK / CLI | `crates/distributionx-client/`, `crates/distributionx-cli/` |
| Logos module SDK | `distributionx_client_module/` |
| Basecamp GUI and LGX assets | `basecamp-app/`, `bash scripts/package.sh` |
| Deterministic error codes | `crates/distributionx-program/src/errors.rs`, `idl/distributionx.idl.json` |
| Retry safety after failed claim | `atomicity_failed_transfer_rolls_back_nullifier.rs`, `claim_atomicity.rs` |
| Proof time and LEZ operation cost | [docs/bench/REPORT.md](docs/bench/REPORT.md) |
| E2E local sequencer demo with `RISC0_DEV_MODE=0` | `bash scripts/e2e.sh ci-localnet` |
| CI coverage | `.github/workflows/distributionx-ci.yml` |
| License | `LICENSE-MIT`, `LICENSE-APACHE` |
| FURPS self-assessment and upstream issues | [solutions/DistributionX.md](solutions/DistributionX.md) |

The previous adoption target for three outside-team distributions was dropped by the L-Prize team.

## Recorded Evidence

Historical LEZ testnet run (rc5 PPE; no longer current evidence):

| Field | Value |
|---|---|
| Evidence file | [docs/TESTNET_EVIDENCE.md](docs/TESTNET_EVIDENCE.md) |
| RPC at capture time | `https://testnet.lez.logos.co` (then LEZ v0.2.0-rc5) |
| Program id | `218a07eb268df922ded961fefd7d035752b44d05f4bb5172305fb0bc54506989` |
| Deploy tx | `b4e31be3c5f9e784295869904e217b52da6bfbe81f2146dd756f9827263537bc` |
| Distributions / claims | 2 distributions, 20 witness-private `claim_ppe` claims, 20 settlements |
| Proof mode | PPE (`send_privacy_preserving_tx`), `RISC0_DEV_MODE=0` |
| Verification | every tx resolved via `getTransaction` when captured; sampled IDs returned `null` after the later testnet reset |
| Per-claim CU | 504401 (public execution; under the 32M cap) |

CU values are recorded in [docs/bench/REPORT.md](docs/bench/REPORT.md). Earlier standalone-sequencer runs are preserved under `docs/run-logs/deployment/` as historical context.

## Reviewer Entry Points

Most reviewers only need these commands. Other scripts are helpers called by these entry points.

| Goal | Command | Notes |
|---|---|---|
| Full CLI evidence run | `bash scripts/e2e.sh ci-localnet` | Builds and starts pinned LEZ v0.2.4, then deploys, initializes, funds, proves with `RISC0_DEV_MODE=0`, verifies, claims, rejects a duplicate locally, and closes. |
| Launch Basecamp reviewer app | `bash scripts/start-basecamp.sh --reset-localnet --clean-user-dir` | Builds LGX packages, resets localnet/local state, installs the app, prints `RISC0_DEV_MODE=0`, and opens Basecamp. |
| Build package artifacts only | `bash scripts/package.sh` | Produces and verifies both LGX files plus `target/lgx/SHA256SUMS`. |
| Check local environment | `bash scripts/preflight.sh` | Verifies expected local tools, wallet, RPC, Basecamp, and LGX tooling. |
| Prepare current testnet evidence | `bash scripts/testnet-evidence.sh prepare` | Creates a private quote only; smoke and finish require its exact SHA-256 as separate approvals. |

Helper scripts used by the commands above: `deploy.sh`, `local-submit.sh`, `local-token-mint.sh`, `wallet-bootstrap.sh`, `install-reviewer-fixture.sh`, `extract-cu.sh`, and `prepare-modules.sh`.

## Current Testnet Evidence Operator Handoff

This is a deliberately phased procedure. `prepare` is private and sends no
transactions. `smoke` and `finish` are separate public-write approvals tied to
the same immutable quote digest. Never run either write phase from a dirty tree,
with reviewer fixtures, or with custom-token settlement enabled.

In one private operator shell, set the values documented in `.env.example`,
including a fresh run ID and the exact release tag. The deployer must already be
funded; funding or initializing it is outside the quoted write count.

For evidence, leave `LEZ_DEPLOY_COMMAND`, `LEZ_WALLET_BIN`, and
`LEE_WALLET_HOME_DIR` unset. The helper rejects those inherited overrides. It
uses the canonical v0.2.4 wallet binary, writes a new private wallet config
bound only to the quoted RPC, and copies the canonical version-scoped
`target/lez-v0.2.4-wallet/storage.json` into that private run state when the
upstream wallet needs it. It does not modify the operator's persistent wallet
config. The v0.2.4 program deployment is unsigned, so the deployment receipt
intentionally records no signer attribution.

```bash
export DISTRIBUTIONX_EVIDENCE_RUN_ID=lp0003-v024-yyyymmdd-a
export DISTRIBUTIONX_RELEASE_TAG=v0.1.0
export LEZ_RPC_URL=https://testnet.lez.logos.co
export RISC0_DEV_MODE=0
export DISTRIBUTIONX_USE_CUSTOM_TOKEN_SETTLEMENT=0
export DISTRIBUTIONX_USE_CLAIM_PRIVATE=0
unset DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT
# Also set the funded deployer, native token, future expiry, recovery,
# and relayer described in .env.example. Production evidence always uses the
# canonical pinned LEZ checkout and freshly built in-repository release CLI.

bash scripts/testnet-evidence.sh prepare
quote_sha="$(<"target/testnet-evidence/${DISTRIBUTIONX_EVIDENCE_RUN_ID}/private/quote.sha256")"
printf 'quote SHA-256: %s\n' "${quote_sha}"
```

Stop. Inspect `private/quote.json` without publishing it. Confirm the exact
source commit, tag, RPC/channel fingerprint, accounts, amounts, and write counts.
Only after explicit approval of that digest, run the five-write canary:

```bash
bash scripts/testnet-evidence.sh smoke "${quote_sha}"
```

Stop again. Independently inspect the deployment and first distribution/claim.
Re-running the same `smoke` command revalidates completed journals rather than
rebroadcasting them. Only after a second explicit approval, run the remaining
22 writes and the read-only verifier:

```bash
bash scripts/testnet-evidence.sh finish "${quote_sha}"
bash scripts/testnet-evidence.sh verify
```

The publishable output is only
`target/testnet-evidence/${DISTRIBUTIONX_EVIDENCE_RUN_ID}/public/`: one manifest
and 27 scrubbed RPC captures covering deployment, two init/prefund/fund groups,
and 20 distinct claims. The sibling `private/` tree must never be committed,
uploaded, shown in a video, or copied into documentation. Review the public
manifest, run a final secret scan, then copy only that public directory under the
matching release tag in `docs/testnet-evidence/`.

## Local CI Preflight

Before pushing, run the push/PR checks GitHub Actions will run:

```bash
bash scripts/ci-local.sh all
```

Use `bash scripts/ci-local.sh quick` for a fast preflight, `bash scripts/ci-local.sh rust` for the Rust job, and `bash scripts/ci-local.sh logos` for the Nix/LGX job. The script checks that files required by CI, including `fixtures/reviewer-fast-path/`, are tracked so GitHub Actions can see them.

## Fresh Clone Setup

Required tools: `bash`, `git`, `curl`, `jq`, Docker, `rustup`, and Nix with
flakes enabled for the Basecamp packages. The standalone lifecycle pins Rust
1.94.0, Risc0/r0vm 3.0.5, and LEZ commit
`47eba256479f6f785acbd138834340703cd03401`.

```bash
git clone <repo-url> dist-x
cd dist-x
rustup toolchain install 1.94.0
bash scripts/risc0-setup.sh

lez_dir=.scaffold/cache/repos/lez/v0.2.4
mkdir -p "$(dirname "$lez_dir")"
git init "$lez_dir"
git -C "$lez_dir" remote add origin \
  https://github.com/logos-blockchain/logos-execution-zone.git
git -C "$lez_dir" fetch --depth=1 origin \
  47eba256479f6f785acbd138834340703cd03401
git -C "$lez_dir" checkout --detach FETCH_HEAD
test "$(git -C "$lez_dir" rev-parse HEAD)" = \
  47eba256479f6f785acbd138834340703cd03401
```

Generate the reviewer binaries:

```bash
cargo build --release -p distributionx-cli
cargo build -p distributionx-program --features spel-idl
cargo build -p example_program_deployment_methods
```

This creates the CLI at `target/release/distributionx-cli` and the LEZ program binary at `target/riscv-guest/example_program_deployment_methods/example_program_deployment_programs/riscv32im-risc0-zkvm-elf/release/distributionx.bin`. `scripts/deploy.sh --localnet` also rebuilds these before deployment.

Start a clean local sequencer:

```bash
bash scripts/standalone-sequencer.sh restart --clean
```

Bootstrap a funded local LEZ signer:

```bash
export LEZ_RPC_URL=http://127.0.0.1:3040
export LEZ_DEPLOYER_WALLET="$(bash scripts/wallet-bootstrap.sh)"
```

Set local submit hooks:

```bash
export DISTRIBUTIONX_STATE_DIR=target/distributionx-testnet
export DISTRIBUTIONX_INIT_SUBMIT_COMMAND='bash scripts/local-submit.sh init'
export DISTRIBUTIONX_FUND_SUBMIT_COMMAND='bash scripts/local-submit.sh fund'
export DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND='bash scripts/local-submit.sh claim'
export DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND='bash scripts/local-submit.sh close'
export DISTRIBUTIONX_RELAYER_URL=localnet
export DISTRIBUTIONX_SERIALIZED_LEZ_TX=target/distributionx-testnet/claim.tx
```

Run CLI/localnet preflight:

```bash
bash scripts/preflight.sh --no-basecamp
```

Run `bash scripts/preflight.sh` before Basecamp packaging or LGX verification.

Install the tracked reviewer fixture when you want deterministic local seeds instead of generating fresh sample keys:

```bash
bash scripts/install-reviewer-fixture.sh
```

## Scratch Creation And Claim Test

This is the shortest reviewer path after the pinned LEZ checkout above:

```bash
bash scripts/e2e.sh ci-localnet
```

The E2E script checks the exact digest of Risc0's Groth16 Docker image before
starting, installs the tracked reviewer fixture, starts the pinned standalone
LEZ v0.2.4 sequencer, deploys the program, initializes and funds the airdrop,
generates and verifies a real Risc0 receipt with `RISC0_DEV_MODE=0`, then
submits the shipping `claim_ppe` instruction through LEZ PPE. The native vault
payout is part of that claim transaction. A second CLI attempt is rejected
from local nullifier state with `E_ALREADY_CLAIMED`; this is not presented as
a second on-chain rejection. The run closes the airdrop and prints
`DISTRIBUTIONX_LOCALNET_E2E_PASS`.

By default localnet E2E uses `fixtures/reviewer-fast-path/`. Set `DISTRIBUTIONX_USE_REVIEWER_FIXTURE=0` to generate a fresh fixture with `distributionx-cli sample-fixture`.

## CLI Demo

Reviewer path:

```bash
bash scripts/demo.sh
```

Shielded/private evidence path:

```bash
bash scripts/e2e.sh ci-localnet
```

The E2E run deploys, initializes, funds, proves with `RISC0_DEV_MODE=0`, verifies, submits `claim_ppe`, rejects a duplicate locally, closes, and writes logs under the configured local log directory.

Manual CLI sequence:

```bash
export DISTRIBUTIONX_CLI="${DISTRIBUTIONX_CLI:-$(pwd)/target/release/distributionx-cli}"
export DISTRIBUTIONX_AIRDROP_NAME="${DISTRIBUTIONX_AIRDROP_NAME:-demo-airdrop}"
export DISTRIBUTIONX_FUND_AMOUNT="${DISTRIBUTIONX_FUND_AMOUNT:-3000}"
export DISTRIBUTIONX_EXPIRY_UNIX="${DISTRIBUTIONX_EXPIRY_UNIX:-1893456000}"
: "${LEZ_DEPLOYER_WALLET:?set a funded local LEZ signer}"
: "${DISTRIBUTIONX_RECOVERY_ADDRESS:?set an initialized recovery account}"

cargo build --release -p distributionx-cli
bash scripts/install-reviewer-fixture.sh
TOKEN_JSON="$("$DISTRIBUTIONX_CLI" mint-token --name "${DISTRIBUTIONX_AIRDROP_NAME}-token" --total-supply "$DISTRIBUTIONX_FUND_AMOUNT")"
export DISTRIBUTIONX_TOKEN_ID="$(printf '%s\n' "$TOKEN_JSON" | jq -r .token_id)"
export DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT="$(printf '%s\n' "$TOKEN_JSON" | jq -r .supply_account_id)"
bash scripts/deploy.sh --localnet
"$DISTRIBUTIONX_CLI" init --csv "$DISTRIBUTIONX_STATE_DIR/eligible.csv" --distributor "$LEZ_DEPLOYER_WALLET" --token "$DISTRIBUTIONX_TOKEN_ID" --token-source-account "$DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT" --rpc "$LEZ_RPC_URL" --expiry "$DISTRIBUTIONX_EXPIRY_UNIX" --recovery "$DISTRIBUTIONX_RECOVERY_ADDRESS"
"$DISTRIBUTIONX_CLI" fund --airdrop "$DISTRIBUTIONX_AIRDROP_NAME" --amount "$DISTRIBUTIONX_FUND_AMOUNT"
RISC0_DEV_MODE=0 "$DISTRIBUTIONX_CLI" prove --airdrop "$DISTRIBUTIONX_AIRDROP_NAME" --bundle "$DISTRIBUTIONX_STATE_DIR/bundle.json" --wallet "$DISTRIBUTIONX_STATE_DIR/wallet.seed" --destination-packet "$DISTRIBUTIONX_STATE_DIR/shielded_destination.json"
"$DISTRIBUTIONX_CLI" verify --airdrop "$DISTRIBUTIONX_AIRDROP_NAME" --proof "$DISTRIBUTIONX_STATE_DIR/proof.json"
"$DISTRIBUTIONX_CLI" claim --airdrop "$DISTRIBUTIONX_AIRDROP_NAME" --proof "$DISTRIBUTIONX_STATE_DIR/proof.json" --relayer "$DISTRIBUTIONX_RELAYER_URL" --serialized-lez-tx "$DISTRIBUTIONX_SERIALIZED_LEZ_TX"
```

## Basecamp

```bash
bash scripts/start-basecamp.sh --reset-localnet --clean-user-dir
```

The launcher builds LGX packages, restarts the local sequencer with clean state, resets `target/distributionx-testnet/`, installs the app into `target/basecamp-user/`, loads `.env.local`, sets `RISC0_DEV_MODE=0`, and launches Basecamp.

Package artifacts:

```bash
bash scripts/e2e.sh package
```

| Output | Contains |
|---|---|
| `target/lgx/distributionx-client.lgx` | Logos core module plus `distributionx-cli` |
| `target/lgx/DistributionX-ui.lgx` | Basecamp QML app |
| `target/lgx/SHA256SUMS` | Fixed-order SHA-256 checksums for both packages |

The matching version tag (`v0.1.0` for the current package manifests) publishes
those same verified files as stable assets on the
[GitHub Releases page](https://github.com/Timidan/dist-x/releases), but only after
every CI job, including the real-proof standalone lifecycle, passes. To verify a
published release locally:

```bash
release_tag=<version-tag>
release_dir="$(mktemp -d)"
gh release download "$release_tag" \
  --repo Timidan/dist-x \
  --pattern '*.lgx' \
  --pattern SHA256SUMS \
  --dir "$release_dir"
(cd "$release_dir" && sha256sum --strict --check SHA256SUMS)
lgx verify "$release_dir/distributionx-client.lgx"
lgx verify "$release_dir/DistributionX-ui.lgx"
```

For a clean install-and-load smoke of the exact local archives (official
`lgpm`, isolated home, offscreen Logos host):

```bash
bash scripts/lgx-load-smoke.sh
```

## Multi-claimant Localnet

```bash
cargo run --release -p distributionx-cli -- export-claim-package \
  --airdrop "$DISTRIBUTIONX_AIRDROP_NAME" \
  --out "$DISTRIBUTIONX_STATE_DIR/claim-package.json"

export DISTRIBUTIONX_STATE_DIR=target/distributionx-claimant-1
cargo run --release -p distributionx-cli -- import-claim-package \
  --package target/distributionx-testnet/claim-package.json \
  --out-dir "$DISTRIBUTIONX_STATE_DIR"
cargo run --release -p distributionx-cli -- create-wallet --out-dir "$DISTRIBUTIONX_STATE_DIR"
RISC0_DEV_MODE=0 cargo run --release -p distributionx-cli -- prove \
  --airdrop "$DISTRIBUTIONX_AIRDROP_NAME" \
  --bundle "$DISTRIBUTIONX_STATE_DIR/bundles/$DISTRIBUTIONX_AIRDROP_NAME.json" \
  --wallet "$DISTRIBUTIONX_STATE_DIR/wallet.seed" \
  --destination-packet "$DISTRIBUTIONX_STATE_DIR/shielded_destination.json"
```

## Verification

```bash
bash scripts/ci-local.sh rust
cargo test -p distributionx-bindings -p distributionx-wallet-ref -p distributionx-tree -p distributionx-circuit -p distributionx-program -p distributionx-client -p distributionx-cli -p distributionx-relayer-ref
(tmpdir="$(mktemp -d)" && trap 'rm -rf "$tmpdir"' EXIT && cargo run -q --manifest-path crates/lez-client-gen/Cargo.toml -- --idl-dir idl --out-dir "$tmpdir" && diff -ru "$tmpdir" src/generated)
cargo check -p distributionx-wallet-ref -p distributionx-tree -p distributionx-circuit --no-default-features
cargo build -p example_program_deployment_methods
RISC0_SKIP_BUILD=1 cargo clippy --workspace --all-targets -- -D warnings
(cd distributionx_client_module && nix --extra-experimental-features 'nix-command flakes' build -L .#unit-tests)
(cd basecamp-app && nix --extra-experimental-features 'nix-command flakes' build -L .#integration-test)
bash scripts/package.sh
```

## License

MIT or Apache-2.0.
