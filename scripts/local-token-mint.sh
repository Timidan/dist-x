#!/usr/bin/env bash
set -euo pipefail

# Mint a real LEZ token-program token. Reads {wallet_path, sequencer_url,
# name, total_supply} from stdin, prints TOKEN_MINTED JSON. The created
# def/supply accounts must remain uninitialized — auth-transfer init on
# either would make `wallet token new` fail.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/35d8df0d031315219f94d1546ceb862b0e5b208f}"
WALLET_BIN="${LEZ_REPO}/target/release/wallet"
if [[ ! -x "${WALLET_BIN}" ]]; then
  echo "E_DISTRIBUTIONX_LOCAL_WALLET_MISSING: run 'set -a; source .env.local; set +a; lgs setup'" >&2
  exit 2
fi

default_wallet_home() {
  if [[ -d "${ROOT}/.scaffold/wallet" ]]; then
    printf '%s\n' "${ROOT}/.scaffold/wallet"
  else
    printf '%s\n' "${HOME}/.nssa/wallet"
  fi
}

WALLET_HOME="${NSSA_WALLET_HOME_DIR:-$(default_wallet_home)}"
if [[ ! -f "${WALLET_HOME}/storage.json" ]]; then
  echo "E_DISTRIBUTIONX_WALLET_NOT_BOOTSTRAPPED: ${WALLET_HOME}/storage.json missing" >&2
  echo "  run 'bash scripts/wallet-bootstrap.sh' to create a funded distributor account" >&2
  exit 2
fi
export NSSA_WALLET_HOME_DIR="${WALLET_HOME}"

ADAPTER_DIR="${TMPDIR:-/tmp}/distributionx-local-token-mint-adapter-${UID:-$(id -u)}"
mkdir -p "${ADAPTER_DIR}/src"

cat > "${ADAPTER_DIR}/Cargo.toml" <<EOF
[package]
name = "distributionx-local-token-mint-adapter"
version = "0.1.0"
edition = "2021"

[dependencies]
common = { path = "${LEZ_REPO}/common" }
nssa = { path = "${LEZ_REPO}/nssa" }
nssa_core = { path = "${LEZ_REPO}/nssa/core" }
serde = { version = "1.0.228", features = ["derive"] }
serde_json = "1.0.149"
sequencer_service_rpc = { path = "${LEZ_REPO}/sequencer/service/rpc", features = ["client"] }
tokio = { version = "1.50.0", features = ["rt-multi-thread", "time"] }
url = "2.5.8"
wallet = { path = "${LEZ_REPO}/wallet" }
EOF
cp "${LEZ_REPO}/Cargo.lock" "${ADAPTER_DIR}/Cargo.lock"

cat > "${ADAPTER_DIR}/src/main.rs" <<'EOF'
use common::HashType;
use sequencer_service_rpc::{RpcClient as _, SequencerClientBuilder};
use serde_json::{json, Value};
use std::io::{self, Read};
use std::time::{Duration, Instant};
use url::Url;
use wallet::{
    config::WalletConfigOverrides,
    helperfunctions::{fetch_config_path, fetch_persistent_storage_path},
    program_facades::token::Token,
    WalletCore,
};

fn main() {
    if let Err(err) = run() {
        eprintln!("{err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .map_err(|e| format!("stdin: {e}"))?;
    let payload: Value =
        serde_json::from_str(&input).map_err(|e| format!("payload JSON: {e}"))?;

    let wallet_path = payload
        .get("wallet_path")
        .and_then(Value::as_str)
        .ok_or("missing wallet_path")?;
    let sequencer_url = payload
        .get("sequencer_url")
        .and_then(Value::as_str)
        .ok_or("missing sequencer_url")?;
    let name = payload
        .get("name")
        .and_then(Value::as_str)
        .ok_or("missing name")?
        .to_string();
    let total_supply =
        parse_total_supply(payload.get("total_supply").ok_or("missing total_supply")?)?;

    // sequencer_addr lives in wallet_config.json, not env — override below.
    std::env::set_var("NSSA_WALLET_HOME_DIR", wallet_path);

    let parsed_sequencer: Url = sequencer_url
        .parse()
        .map_err(|e| format!("sequencer_url '{sequencer_url}': {e}"))?;
    let config_path =
        fetch_config_path().map_err(|e| format!("resolve wallet config path: {e}"))?;
    let storage_path = fetch_persistent_storage_path()
        .map_err(|e| format!("resolve wallet storage path: {e}"))?;
    if !storage_path.exists() {
        return Err(format!(
            "E_DISTRIBUTIONX_WALLET_NOT_BOOTSTRAPPED: {} missing — run scripts/wallet-bootstrap.sh first",
            storage_path.display()
        ));
    }

    let overrides = WalletConfigOverrides {
        sequencer_addr: Some(parsed_sequencer),
        ..Default::default()
    };
    let mut wallet_core = WalletCore::new_update_chain(config_path, storage_path, Some(overrides))
        .map_err(|e| format!("wallet init: {e}"))?;

    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    let response = rt.block_on(async {
        let (def_id, _) = wallet_core.create_new_account_public(None);
        let (supply_id, _) = wallet_core.create_new_account_public(None);

        let tx_hash: HashType = Token(&wallet_core)
            .send_new_definition(def_id, supply_id, name.clone(), total_supply)
            .await
            .map_err(|e| format!("token send_new_definition: {e:?}"))?;

        // Persist the new accounts only AFTER the tx is accepted by the sequencer.
        // If the tx fails, no orphan ids are left in storage.json.
        wallet_core
            .store_persistent_data()
            .await
            .map_err(|e| format!("store after mint: {e}"))?;

        // 180s default — the prior 60s window was too short under load.
        let timeout_secs = std::env::var("DISTRIBUTIONX_TX_CONFIRM_TIMEOUT_SECS")
            .ok()
            .and_then(|raw| raw.parse::<u64>().ok())
            .unwrap_or(180);
        let client = SequencerClientBuilder::default()
            .build(sequencer_url)
            .map_err(|e| format!("connect {sequencer_url}: {e}"))?;
        let started = Instant::now();
        let mut last_error: Option<String> = None;
        loop {
            match client.get_transaction(tx_hash).await {
                Ok(Some(_)) => break,
                Ok(None) => {}
                Err(err) => last_error = Some(err.to_string()),
            }
            if started.elapsed().as_secs() >= timeout_secs {
                let detail = last_error
                    .map(|err| format!(" last RPC error: {err}"))
                    .unwrap_or_default();
                return Err(format!(
                    "E_DISTRIBUTIONX_TX_NOT_INCLUDED: token mint tx {tx_hash} not visible after {timeout_secs}s.{detail}"
                ));
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }

        Ok::<_, String>(json!({
            "status": "TOKEN_MINTED",
            "token_id": format!("Public/{def_id}"),
            "definition_account_id": format!("Public/{def_id}"),
            "supply_account_id": format!("Public/{supply_id}"),
            "tx_hash": tx_hash.to_string(),
            "name": name,
            "total_supply": total_supply.to_string(),
            "note": "registered via LEZ token program; airdrop disbursement still uses native LEZ"
        }))
    })?;

    println!("{response}");
    Ok(())
}

fn parse_total_supply(value: &Value) -> Result<u128, String> {
    if let Some(n) = value.as_u64() {
        return Ok(u128::from(n));
    }
    if let Some(s) = value.as_str() {
        return s.parse::<u128>().map_err(|e| format!("total_supply: {e}"));
    }
    Err(format!(
        "total_supply must be u64 or numeric string, got: {value}"
    ))
}
EOF

ADAPTER_STDOUT="${ADAPTER_DIR}/stdout.log"
if cargo run -q --offline --manifest-path "${ADAPTER_DIR}/Cargo.toml" >"${ADAPTER_STDOUT}"; then
  tail -n 1 "${ADAPTER_STDOUT}"
else
  cat "${ADAPTER_STDOUT}" >&2
  exit 1
fi
