#!/usr/bin/env bash
set -euo pipefail

# Drive local LEZ token-program operations. Reads JSON on stdin.
# op=mint creates definition/supply accounts and prints TOKEN_MINTED.
# op=query reads a token holding account and prints QUERY_BALANCE_OK.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

CALLER_HAD_STATE_DIR=0
CALLER_DISTRIBUTIONX_STATE_DIR="${DISTRIBUTIONX_STATE_DIR:-}"
if [[ -v DISTRIBUTIONX_STATE_DIR ]]; then
  CALLER_HAD_STATE_DIR=1
fi

ENV_FILE="${DISTRIBUTIONX_ENV_FILE:-${ROOT}/.env.local}"
if [[ -r "${ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
fi
if [[ "${CALLER_HAD_STATE_DIR}" == "1" ]]; then
  export DISTRIBUTIONX_STATE_DIR="${CALLER_DISTRIBUTIONX_STATE_DIR}"
fi

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/v0.2.4}"
bash "${ROOT}/scripts/lez-source-guard.sh" "${LEZ_REPO}" >/dev/null
WALLET_BIN="${LEZ_WALLET_BIN:-${ROOT}/target/lez-v0.2.4-build/release/wallet}"
if [[ ! -x "${WALLET_BIN}" && "${DISTRIBUTIONX_LOCAL_TOKEN_COMPILE_ONLY:-0}" != "1" ]]; then
  echo "E_DISTRIBUTIONX_LOCAL_WALLET_MISSING: ${WALLET_BIN}" >&2
  exit 2
fi

WALLET_HOME="${LEE_WALLET_HOME_DIR:-${ROOT}/target/lez-v0.2.4-wallet}"
if [[ ! -f "${WALLET_HOME}/storage.json" && "${DISTRIBUTIONX_LOCAL_TOKEN_COMPILE_ONLY:-0}" != "1" ]]; then
  echo "E_DISTRIBUTIONX_WALLET_NOT_BOOTSTRAPPED: ${WALLET_HOME}/storage.json missing" >&2
  echo "  run 'bash scripts/wallet-bootstrap.sh' to create a funded distributor account" >&2
  exit 2
fi
export LEE_WALLET_HOME_DIR="${WALLET_HOME}"

export CARGO_HOME="${CARGO_HOME:-${ROOT}/target/cargo-home}"
export LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-${ROOT}/vendor/logos-blockchain-circuits}"
default_lbc_root_dir() {
  local cached="${HOME}/.cache/logos/blockchain/logos-blockchain-circuits-v0.5.3-linux-x86_64"
  if [[ -d "${LOGOS_BLOCKCHAIN_CIRCUITS}/signature" && -d "${LOGOS_BLOCKCHAIN_CIRCUITS}/lib" ]]; then
    printf '%s\n' "${LOGOS_BLOCKCHAIN_CIRCUITS}"
  elif [[ -d "${cached}/signature" && -d "${cached}/lib" ]]; then
    printf '%s\n' "${cached}"
  else
    printf '%s\n' "${LOGOS_BLOCKCHAIN_CIRCUITS}"
  fi
}
export LBC_ROOT_DIR="${LBC_ROOT_DIR:-$(default_lbc_root_dir)}"

ADAPTER_ROOT="${DISTRIBUTIONX_ADAPTER_CACHE_DIR:-${ROOT}/target/distributionx-adapters}"
ADAPTER_DIR="${ADAPTER_ROOT}/local-token-mint-${UID:-$(id -u)}"
export CARGO_TARGET_DIR="${DISTRIBUTIONX_ADAPTER_TARGET_DIR:-${ROOT}/target/lez-v0.2.4-build}"
mkdir -p "${ADAPTER_DIR}/src" "${ADAPTER_ROOT}/tmp"
export TMPDIR="${ADAPTER_ROOT}/tmp"

cat > "${ADAPTER_DIR}/Cargo.toml" <<EOF
[package]
name = "distributionx-lez-adapter"
version = "0.1.0"
edition = "2021"

[workspace]

[dependencies]
common = { path = "${LEZ_REPO}/lez/common" }
hex = "0.4.3"
lee = { path = "${LEZ_REPO}/lee/state_machine" }
lee_core = { path = "${LEZ_REPO}/lee/state_machine/core", features = ["host"] }
serde = { version = "1.0.228", features = ["derive"] }
serde_json = "1.0.149"
sequencer_service_rpc = { path = "${LEZ_REPO}/lez/sequencer/service/rpc", features = ["client"] }
sha2 = "0.10.9"
tokio = { version = "1.50.0", features = ["rt-multi-thread", "time"] }
token_core = { path = "${LEZ_REPO}/lez/programs/token/core" }
url = "2.5.8"
wallet = { path = "${LEZ_REPO}/lez/wallet" }
EOF
cp "${ROOT}/scripts/adapter-lock/Cargo.lock" "${ADAPTER_DIR}/Cargo.lock"
cargo +1.94.0 fetch -q --locked --manifest-path "${ADAPTER_DIR}/Cargo.toml"

cat > "${ADAPTER_DIR}/src/main.rs" <<'EOF'
use common::HashType;
use lee::{Account, AccountId};
use sequencer_service_rpc::{RpcClient as _, SequencerClientBuilder};
use serde_json::{json, Value};
use std::io::{self, Read};
use std::path::PathBuf;
use std::time::{Duration, Instant};
use token_core::TokenHolding;
use wallet::{
    AccountIdentity,
    config::{SequencerConnectionData, WalletConfigOverrides},
    helperfunctions::{fetch_config_path, fetch_persistent_storage_path, fetch_statistics_path},
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

    let op = payload
        .get("op")
        .and_then(Value::as_str)
        .unwrap_or("mint");
    match op {
        "mint" => mint_token(&payload),
        "query" => query_token_balance(&payload),
        other => Err(format!("unknown token helper op: {other}")),
    }
}

fn open_wallet(payload: &Value) -> Result<WalletCore, String> {
    let wallet_path = payload
        .get("wallet_path")
        .and_then(Value::as_str)
        .ok_or("missing wallet_path")?;
    let sequencer_url = payload
        .get("sequencer_url")
        .and_then(Value::as_str)
        .ok_or("missing sequencer_url")?;

    // sequencer_addr lives in wallet_config.json, not env — override below.
    std::env::set_var("LEE_WALLET_HOME_DIR", wallet_path);

    let parsed_sequencer = sequencer_url
        .parse()
        .map_err(|e| format!("sequencer_url '{sequencer_url}': {e}"))?;
    let config_path =
        fetch_config_path().map_err(|e| format!("resolve wallet config path: {e}"))?;
    let storage_path = fetch_persistent_storage_path()
        .map_err(|e| format!("resolve wallet storage path: {e}"))?;
    let statistics_path =
        fetch_statistics_path().map_err(|e| format!("resolve wallet statistics path: {e}"))?;
    if !storage_path.exists() {
        return Err(format!(
            "E_DISTRIBUTIONX_WALLET_NOT_BOOTSTRAPPED: {} missing — run scripts/wallet-bootstrap.sh first",
            storage_path.display()
        ));
    }

    let overrides = WalletConfigOverrides {
        sequencers: Some(vec![SequencerConnectionData {
            sequencer_addr: parsed_sequencer,
            basic_auth: None,
        }]),
        ..Default::default()
    };
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    rt.block_on(WalletCore::new_update_chain(
        config_path,
        storage_path,
        statistics_path,
        Some(overrides),
    ))
    .map_err(|e| format!("wallet init: {e}"))
}

fn mint_token(payload: &Value) -> Result<(), String> {
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
    let mut wallet_core = open_wallet(payload)?;

    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    let response = rt.block_on(async {
        let (def_id, _) = wallet_core.create_new_account_public(None);
        let (supply_id, _) = wallet_core.create_new_account_public(None);

        let tx_hash: HashType = Token(&wallet_core)
            .send_new_definition(
                AccountIdentity::Public(def_id),
                AccountIdentity::Public(supply_id),
                name.clone(),
                total_supply,
            )
            .await
            .map_err(|e| format!("token send_new_definition: {e:?}"))?;

        // Persist the new accounts only AFTER the tx is accepted by the sequencer.
        // If the tx fails, no orphan ids are left in storage.json.
        wallet_core
            .store_persistent_data()
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
        let block_id = loop {
            match client.get_transaction(tx_hash).await {
                Ok(Some((_transaction, block_id))) => break block_id,
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
        };

        Ok::<_, String>(json!({
            "status": "TOKEN_MINTED",
            "token_id": format!("Public/{def_id}"),
            "definition_account_id": format!("Public/{def_id}"),
            "supply_account_id": format!("Public/{supply_id}"),
            "tx_hash": tx_hash.to_string(),
            "block_id": block_id,
            "name": name,
            "total_supply": total_supply.to_string(),
            "note": "registered via LEZ token program; claims settle by token-program transfer from the supply account"
        }))
    })?;

    println!("{response}");
    Ok(())
}

fn query_token_balance(payload: &Value) -> Result<(), String> {
    let account = payload
        .get("account")
        .and_then(Value::as_str)
        .ok_or("missing account")?;
    let token = payload
        .get("token")
        .and_then(Value::as_str)
        .ok_or("missing token")?;
    let account_id = parse_account_id(account)?;
    let expected_definition = parse_account_id(token)?;
    if let Some(response) = recorded_shielded_balance(account, token)? {
        println!("{response}");
        return Ok(());
    }
    let wallet_core = open_wallet(payload)?;
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    let response = rt.block_on(async {
        let private_account = wallet_core.get_account_private(account_id);
        let (account_data, account_state) = if let Some(account_data) = private_account {
            (account_data, "private_holding")
        } else {
            let public_account = wallet_core
                .get_account_public(account_id)
                .await
                .map_err(|e| format!("query token account {account}: {e}"))?;
            (public_account, "public_holding")
        };
        if account_data == Account::default() {
            return Ok::<_, String>(json!({
                "status": "QUERY_BALANCE_OK",
                "account": account,
                "token": token,
                "asset": "lez_token_program",
                "account_state": "uninitialized",
                "balance": "0",
                "definition_id": format!("Public/{expected_definition}")
            }));
        }
        let holding = TokenHolding::try_from(&account_data.data)
            .map_err(|_| format!("E_TOKEN_ACCOUNT_NOT_HOLDING: {account} is not a token holding account"))?;
        match holding {
            TokenHolding::Fungible {
                definition_id,
                balance,
            } => {
                if definition_id != expected_definition {
                    return Err(format!(
                        "E_TOKEN_DEFINITION_MISMATCH: account holds Public/{definition_id}, expected Public/{expected_definition}"
                    ));
                }
                Ok(json!({
                    "status": "QUERY_BALANCE_OK",
                    "account": account,
                    "token": token,
                    "asset": "lez_token_program",
                    "account_state": account_state,
                    "balance": balance.to_string(),
                    "definition_id": format!("Public/{definition_id}")
                }))
            }
            _ => Err(format!("E_UNSUPPORTED_TOKEN_HOLDING: {account} is not a fungible token account")),
        }
    })?;
    println!("{response}");
    Ok(())
}

fn recorded_shielded_balance(account: &str, token: &str) -> Result<Option<Value>, String> {
    let path = std::env::var("DISTRIBUTIONX_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("target/distributionx-testnet"))
        .join("shielded_token_balances.json");
    if !path.exists() {
        return Ok(None);
    }
    let document: Value = serde_json::from_slice(
        &std::fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?,
    )
    .map_err(|e| format!("parse {}: {e}", path.display()))?;
    let Some(entries) = document.get("balances").and_then(Value::as_array) else {
        return Ok(None);
    };
    let Some(entry) = entries.iter().find(|entry| {
        entry
            .get("account")
            .and_then(Value::as_str)
            .is_some_and(|value| ids_match(value, account))
            && entry
                .get("token")
                .and_then(Value::as_str)
                .is_some_and(|value| ids_match(value, token))
    }) else {
        return Ok(None);
    };
    Ok(Some(json!({
        "status": "QUERY_BALANCE_OK",
        "account": account,
        "token": token,
        "asset": "lez_token_program",
        "account_state": "shielded_settlement",
        "balance": entry.get("balance").and_then(Value::as_str).unwrap_or("0"),
        "definition_id": token,
        "last_tx_id": entry.get("last_tx_id").and_then(Value::as_str).unwrap_or("")
    })))
}

fn ids_match(left: &str, right: &str) -> bool {
    if let (Ok(left_id), Ok(right_id)) = (parse_account_id(left), parse_account_id(right)) {
        return left_id == right_id;
    }
    normalize_id(left) == normalize_id(right)
}

fn normalize_id(value: &str) -> &str {
    let trimmed = value.trim();
    if let Some((prefix, rest)) = trimmed.split_once('/') {
        if prefix == "Public" || prefix == "Private" {
            return rest;
        }
    }
    trimmed
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

fn parse_account_id(value: &str) -> Result<AccountId, String> {
    let trimmed = value.trim();
    let normalized = trimmed
        .strip_prefix("Public/")
        .or_else(|| trimmed.strip_prefix("Private/"))
        .unwrap_or(trimmed);
    if normalized.len() == 64 && normalized.chars().all(|ch| ch.is_ascii_hexdigit()) {
        let bytes = hex::decode(normalized).map_err(|e| format!("account id hex {value}: {e}"))?;
        let fixed: [u8; 32] = bytes
            .try_into()
            .map_err(|bytes: Vec<u8>| format!("expected 32-byte account id, got {}", bytes.len()))?;
        return Ok(AccountId::new(fixed));
    }
    normalized
        .parse()
        .map_err(|e| format!("account id {value}: {e}"))
}
EOF

ADAPTER_STDOUT="${ADAPTER_DIR}/stdout.log"
if [[ "${DISTRIBUTIONX_LOCAL_TOKEN_COMPILE_ONLY:-0}" == "1" ]]; then
  cargo +1.94.0 check -q --locked --release --offline --manifest-path "${ADAPTER_DIR}/Cargo.toml"
  echo "DISTRIBUTIONX_LOCAL_TOKEN_ADAPTER_COMPILE_OK"
  exit 0
fi
if cargo +1.94.0 run -q --locked --release --offline --manifest-path "${ADAPTER_DIR}/Cargo.toml" >"${ADAPTER_STDOUT}"; then
  tail -n 1 "${ADAPTER_STDOUT}"
else
  cat "${ADAPTER_STDOUT}" >&2
  exit 1
fi
