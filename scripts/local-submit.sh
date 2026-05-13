#!/usr/bin/env bash
set -euo pipefail

op="${1:-}"
if [[ "${op}" != "init" && "${op}" != "fund" && "${op}" != "claim" && "${op}" != "close" ]]; then
  echo "usage: scripts/local-submit.sh init|fund|claim|close" >&2
  exit 64
fi

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

LEZ_REPO="${DISTRIBUTIONX_LEZ_REPO:-${ROOT}/.scaffold/cache/repos/lez/35d8df0d031315219f94d1546ceb862b0e5b208f}"
WALLET_BIN="${LEZ_REPO}/target/release/wallet"
if [[ ! -x "${WALLET_BIN}" ]]; then
  echo "E_DISTRIBUTIONX_LOCAL_WALLET_MISSING: run 'set -a; source .env.local; set +a; lgs setup'" >&2
  exit 2
fi
# `wallet check-health` consumes stdin and auto-inits storage — unsafe in a
# submit hook. Just verify storage exists.
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

is_local_rpc() {
  local value="${LEZ_RPC_URL:-}"
  [[ "${value}" == http://127.0.0.1* ||
     "${value}" == http://localhost* ||
     "${value}" == http://[[]::1[]]* ]]
}

ensure_local_deployment() {
  local state_dir="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}"
  local deployment="${state_dir}/deployment.json"
  if [[ -f "${deployment}" ]]; then
    return
  fi
  export LEZ_RPC_URL="${LEZ_RPC_URL:-http://127.0.0.1:3040}"
  if ! is_local_rpc; then
    echo "E_DISTRIBUTIONX_DEPLOYMENT_MISSING: ${deployment}" >&2
    exit 2
  fi
  export DISTRIBUTIONX_STATE_DIR="${state_dir}"
  bash "${ROOT}/scripts/deploy.sh" --localnet >&2
}

ensure_local_deployment

export DISTRIBUTIONX_REPO_ROOT="${ROOT}"
export DISTRIBUTIONX_LEZ_REPO="${LEZ_REPO}"
export LOGOS_BLOCKCHAIN_CIRCUITS="${LOGOS_BLOCKCHAIN_CIRCUITS:-${ROOT}/vendor/logos-blockchain-circuits}"

ADAPTER_ROOT="${DISTRIBUTIONX_ADAPTER_CACHE_DIR:-${ROOT}/target/distributionx-adapters}"
ADAPTER_DIR="${ADAPTER_ROOT}/local-submit-${UID:-$(id -u)}"
mkdir -p "${ADAPTER_DIR}/src" "${ADAPTER_ROOT}/tmp"
export TMPDIR="${ADAPTER_ROOT}/tmp"
export DISTRIBUTIONX_LEZ_CU_LOG="${DISTRIBUTIONX_LEZ_CU_LOG:-/tmp/distributionx-standalone-sequencer-${UID:-$(id -u)}.log}"

cat > "${ADAPTER_DIR}/Cargo.toml" <<EOF
[package]
name = "distributionx-local-submit-adapter"
version = "0.1.0"
edition = "2021"

[workspace]

[dependencies]
common = { path = "${LEZ_REPO}/common" }
hex = "0.4.3"
url = "2.5.8"
nssa = { path = "${LEZ_REPO}/nssa" }
nssa_core = { path = "${LEZ_REPO}/nssa/core" }
serde = { version = "1.0.228", features = ["derive"] }
serde_json = "1.0.149"
sequencer_service_rpc = { path = "${LEZ_REPO}/sequencer/service/rpc", features = ["client"] }
sha2 = "0.10.9"
tokio = { version = "1.50.0", features = ["rt-multi-thread", "time"] }
wallet = { path = "${LEZ_REPO}/wallet" }
EOF
cp "${LEZ_REPO}/Cargo.lock" "${ADAPTER_DIR}/Cargo.lock"
perl -0pe '
  s#^//!#//#mg;
  s#let airdrop_id = serde_json::from_value#let airdrop_id: [u8; 32] = serde_json::from_value#g;
  s#let nullifier = serde_json::from_value#let nullifier: [u8; 32] = serde_json::from_value#g;
  s#Ok\(AccountId::for_public_pda\(program_id, &PdaSeed::new\(pda_seed_bytes\(seeds\)\?\)\)\)#Ok(AccountId::from((program_id, &PdaSeed::new(pda_seed_bytes(seeds)?))))#g;
  s#AccountId::for_public_pda\(program_id, &pda_seed\)#AccountId::from((program_id, &pda_seed))#g;
  s#fn init_wallet\(v: &Value\) -> Result<WalletCore, String> \{.*?\n\}\n#fn init_wallet(v: \&Value) -> Result<WalletCore, String> \{\n    super::open_wallet(v)\n\}\n#s;
' "${ROOT}/src/generated/distributionx_ffi.rs" > "${ADAPTER_DIR}/src/generated_distributionx_ffi.rs"

cat > "${ADAPTER_DIR}/src/main.rs" <<'EOF'
use common::{HashType, transaction::NSSATransaction};
use nssa::{AccountId, ProgramId};
use nssa_core::{NullifierPublicKey, program::PdaSeed};
use nssa_core::encryption::shared_key_derivation::Secp256k1Point;
use serde_json::{json, Value};
use sequencer_service_rpc::{RpcClient as _, SequencerClientBuilder};
use sha2::{Digest as _, Sha256};
use std::ffi::{CStr, CString};
use std::io::{self, Read};
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use url::Url;
use wallet::{
    AccDecodeData,
    config::WalletConfigOverrides,
    helperfunctions::{fetch_config_path, fetch_persistent_storage_path},
    program_facades::native_token_transfer::NativeTokenTransfer,
    program_facades::token::Token,
    WalletCore,
};

fn open_wallet(args: &Value) -> Result<WalletCore, String> {
    let wallet_path = required_str(args, "wallet_path")?;
    let sequencer_url = required_str(args, "sequencer_url")?;
    std::env::set_var("NSSA_WALLET_HOME_DIR", wallet_path);
    let parsed: Url = sequencer_url
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
        sequencer_addr: Some(parsed),
        ..Default::default()
    };
    WalletCore::new_update_chain(config_path, storage_path, Some(overrides))
        .map_err(|e| format!("wallet init: {e}"))
}

fn claim_has_private_payload(args: &Value) -> bool {
    args.get("private_claim").is_some()
        && args.get("recipient_npk").is_some()
        && args.get("recipient_vpk").is_some()
}

// The demo default is the receipt-based `claim` instruction, where the witness
// stays inside the Risc0 zkVM. Setting DISTRIBUTIONX_USE_CLAIM_PRIVATE=1 opts
// into the in-program `claim_private` verifier, which carries the witness in
// instruction args and therefore does not preserve observer privacy.
fn claim_private_opt_in() -> bool {
    matches!(
        std::env::var("DISTRIBUTIONX_USE_CLAIM_PRIVATE")
            .ok()
            .as_deref()
            .map(str::trim),
        Some("1") | Some("true") | Some("yes") | Some("on")
    )
}

fn should_use_private_claim(op: &str, args: &Value) -> Result<bool, String> {
    if op != "claim" {
        return Ok(false);
    }
    if !claim_private_opt_in() {
        return Ok(false);
    }
    if !claim_has_private_payload(args) {
        return Err(
            "E_DISTRIBUTIONX_PRIVATE_CLAIM_REQUIRED: DISTRIBUTIONX_USE_CLAIM_PRIVATE is set but \
             payload lacks private_claim/recipient_npk/recipient_vpk"
                .to_owned(),
        );
    }
    Ok(true)
}

mod generated {
    #![allow(dead_code, unused_imports, unused_mut)]

    include!("generated_distributionx_ffi.rs");
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err}");
        std::process::exit(1);
    }
}

fn run() -> Result<(), String> {
    let op = std::env::args().nth(1).ok_or("missing op")?;
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .map_err(|e| format!("stdin: {e}"))?;
    let payload: Value = serde_json::from_str(&input).map_err(|e| format!("payload JSON: {e}"))?;
    let args = match op.as_str() {
        "init" => init_args(&payload)?,
        "fund" => fund_args(&payload)?,
        "claim" => claim_args(&payload)?,
        "close" => close_args(&payload)?,
        _ => return Err(format!("unknown op: {op}")),
    };
    if op == "fund" {
        prefund_vault(&args)?;
    }
    let use_private_claim = should_use_private_claim(&op, &args)?;
    let response = if use_private_claim {
        call_generated("claim_private", &args)?
    } else {
        call_generated(&op, &args)?
    };
    let tx_hash = response
        .get("tx_hash")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("generated response missing tx_hash: {response}"))?;
    if let Err(err) = wait_for_transaction(tx_hash) {
        write_receipt(&op, tx_hash, "SUBMITTED_NOT_CONFIRMED", None, Some(&err), None)?;
        return Err(err);
    }
    let token_tx_hash = if op == "claim" {
        settle_claim_tokens(&args)?
    } else {
        None
    };
    if let Some(token_tx) = token_tx_hash.as_deref() {
        if let Err(err) = wait_for_transaction(token_tx) {
            write_receipt(&op, tx_hash, "TOKEN_SUBMITTED_NOT_CONFIRMED", None, Some(&err), Some(token_tx))?;
            return Err(err);
        }
    }
    write_receipt(&op, tx_hash, "OK", None, None, token_tx_hash.as_deref())?;
    println!("{}", json!({
        "tx_id": tx_hash,
        "token_tx_id": token_tx_hash,
        "submit_mode": if use_private_claim { "claim_private" } else { op.as_str() }
    }));
    Ok(())
}

fn write_receipt(
    op: &str,
    tx_hash: &str,
    status: &str,
    cu: Option<u64>,
    note: Option<&str>,
    token_tx_hash: Option<&str>,
) -> Result<(), String> {
    let receipts_dir = std::env::var("DISTRIBUTIONX_RECEIPTS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| state_dir().join("receipts"));
    std::fs::create_dir_all(&receipts_dir)
        .map_err(|e| format!("create receipts dir {}: {e}", receipts_dir.display()))?;
    let receipt_name = if op == "init" { "init_airdrop" } else { op };
    let path = receipts_dir.join(format!("{receipt_name}.json"));
    let payload = json!({
        "tx_id": tx_hash,
        "status": status,
        "cu": cu,
        "token_tx_id": token_tx_hash,
        "captured_from": "scripts/local-submit.sh",
        "note": note,
    });
    std::fs::write(&path, serde_json::to_vec_pretty(&payload).map_err(|e| format!("receipt JSON: {e}"))?)
        .map_err(|e| format!("write receipt {}: {e}", path.display()))?;
    Ok(())
}

fn prefund_vault(args: &Value) -> Result<(), String> {
    let program_id = parse_program_id_hex(required_str(args, "program_id_hex")?)?;
    let airdrop_id: [u8; 32] = serde_json::from_value(
        args.get("airdrop_id").cloned().ok_or("missing airdrop_id")?,
    )
    .map_err(|e| format!("airdrop_id: {e}"))?;
    let distributor = parse_account_id(required_str(args, "distributor")?)?;
    let amount = args
        .get("amount")
        .and_then(Value::as_u64)
        .ok_or("missing amount")? as u128;
    let vault = compute_pda_with_program(&program_id, &[b"vault", airdrop_id.as_ref()])?;

    let wallet = open_wallet(args)?;
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    rt.block_on(async {
        let current = wallet
            .get_account_balance(vault)
            .await
            .map_err(|e| format!("vault balance: {e}"))?;
        if current >= amount {
            return Ok(());
        }
        let delta = amount - current;
        let tx_hash = NativeTokenTransfer(&wallet)
            .send_public_transfer(distributor, vault, delta)
            .await
            .map_err(|e| format!("vault transfer: {e}"))?;
        wallet
            .poll_native_token_transfer(tx_hash)
            .await
            .map_err(|e| format!("vault transfer inclusion: {e}"))?;
        wallet
            .store_persistent_data()
            .await
            .map_err(|e| format!("wallet store: {e}"))?;
        Ok::<(), String>(())
    })
}

fn settle_claim_tokens(args: &Value) -> Result<Option<String>, String> {
    let Some(settlement) = args.get("token_settlement") else {
        return Ok(None);
    };
    if settlement.is_null() {
        return Ok(None);
    }
    let source = parse_account_id(required_str(settlement, "source_account")?)?;
    let recipient = parse_account_id(required_str(settlement, "recipient_account")?)?;
    let amount = settlement
        .get("amount")
        .and_then(Value::as_u64)
        .ok_or("missing token_settlement.amount")?;
    if amount == 0 {
        return Ok(None);
    }

    let mut wallet = open_wallet(args)?;
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    rt.block_on(async {
        let tx_hash = if let (Some(npk), Some(vpk)) = (
            args.get("recipient_npk").and_then(Value::as_str),
            args.get("recipient_vpk").and_then(Value::as_str),
        ) {
            let recipient_npk = NullifierPublicKey(parse_hex_32(npk)?);
            let recipient_vpk = Secp256k1Point(hex::decode(vpk)
                .map_err(|e| format!("recipient_vpk hex: {e}"))?);
            let (tx_hash, secret_recipient) = Token(&wallet)
                .send_transfer_transaction_shielded_foreign_account(
                    source,
                    recipient_npk,
                    recipient_vpk,
                    u128::from(amount),
                )
                .await
                .map_err(|e| format!("shielded token claim transfer: {e:?}"))?;
            let transfer_tx = wallet
                .poll_native_token_transfer(tx_hash)
                .await
                .map_err(|e| format!("shielded token claim transfer inclusion: {e}"))?;
            if let NSSATransaction::PrivacyPreserving(tx) = transfer_tx {
                wallet
                    .decode_insert_privacy_preserving_transaction_results(
                        &tx,
                        &[AccDecodeData::Decode(secret_recipient, recipient)],
                    )
                    .map_err(|e| format!("decode shielded token account: {e}"))?;
            }
            record_shielded_token_settlement(settlement, &tx_hash.to_string(), amount)?;
            tx_hash
        } else {
            Token(&wallet)
                .send_transfer_transaction(source, recipient, u128::from(amount))
                .await
                .map_err(|e| format!("token claim transfer: {e:?}"))?
        };
        wallet
            .store_persistent_data()
            .await
            .map_err(|e| format!("wallet store after token transfer: {e}"))?;
        Ok::<_, String>(Some(tx_hash.to_string()))
    })
}

fn record_shielded_token_settlement(
    settlement: &Value,
    tx_hash: &str,
    amount: u64,
) -> Result<(), String> {
    let recipient = required_str(settlement, "recipient_account")?;
    let token = required_str(settlement, "token_id")?;
    let path = state_dir().join("shielded_token_balances.json");
    let mut document = if path.exists() {
        serde_json::from_slice::<Value>(
            &std::fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?,
        )
        .map_err(|e| format!("parse {}: {e}", path.display()))?
    } else {
        json!({ "balances": [] })
    };
    if !document.get("balances").is_some_and(Value::is_array) {
        document["balances"] = json!([]);
    }
    let balances = document["balances"]
        .as_array_mut()
        .ok_or("shielded balance ledger is not an array")?;
    if let Some(entry) = balances.iter_mut().find(|entry| {
        entry.get("account").and_then(Value::as_str) == Some(recipient)
            && entry.get("token").and_then(Value::as_str) == Some(token)
    }) {
        let current = entry
            .get("balance")
            .and_then(Value::as_str)
            .and_then(|raw| raw.parse::<u128>().ok())
            .unwrap_or(0);
        entry["balance"] = json!((current + u128::from(amount)).to_string());
        entry["last_tx_id"] = json!(tx_hash);
        entry["updated_at_unix"] = json!(now_unix());
    } else {
        balances.push(json!({
            "account": recipient,
            "token": token,
            "balance": amount.to_string(),
            "last_tx_id": tx_hash,
            "updated_at_unix": now_unix(),
        }));
    }
    std::fs::write(
        &path,
        serde_json::to_vec_pretty(&document).map_err(|e| format!("settlement ledger JSON: {e}"))?,
    )
    .map_err(|e| format!("write {}: {e}", path.display()))
}

fn wait_for_transaction(tx_hash: &str) -> Result<(), String> {
    let hash: HashType = tx_hash
        .parse()
        .map_err(|e| format!("invalid tx_hash {tx_hash}: {e}"))?;
    let rpc_url = std::env::var("LEZ_RPC_URL").unwrap_or_else(|_| "http://127.0.0.1:3040".to_owned());
    // 180s default — the prior 30s window was too short under load.
    let timeout_secs = std::env::var("DISTRIBUTIONX_TX_CONFIRM_TIMEOUT_SECS")
        .ok()
        .and_then(|raw| raw.parse::<u64>().ok())
        .unwrap_or(180);
    let rt = tokio::runtime::Runtime::new().map_err(|e| format!("tokio runtime: {e}"))?;
    rt.block_on(async {
        let client = SequencerClientBuilder::default()
            .build(rpc_url.as_str())
            .map_err(|e| format!("connect {rpc_url}: {e}"))?;
        let timeout = Duration::from_secs(timeout_secs);
        let started = Instant::now();
        let mut last_error = None;
        loop {
            match client.get_transaction(hash).await {
                Ok(Some(_)) => return Ok(()),
                Ok(None) => {}
                Err(err) => last_error = Some(err.to_string()),
            }
            if let Some(detail) = rejected_transaction_detail(tx_hash) {
                return Err(format!("E_DISTRIBUTIONX_TX_REJECTED: {tx_hash} {detail}"));
            }
            if started.elapsed() >= timeout {
                let detail = last_error
                    .map(|err| format!(" last RPC error: {err}"))
                    .unwrap_or_default();
                return Err(format!(
                    "E_DISTRIBUTIONX_TX_NOT_INCLUDED: {tx_hash} was not visible after {timeout_secs}s.{detail}"
                ));
            }
            tokio::time::sleep(Duration::from_millis(500)).await;
        }
    })
}

fn rejected_transaction_detail(tx_hash: &str) -> Option<String> {
    let path = std::env::var("DISTRIBUTIONX_LEZ_CU_LOG").ok()?;
    let log = std::fs::read_to_string(path).ok()?;
    log.lines()
        .rev()
        .find(|line| line.contains(tx_hash) && line.contains("failed execution check"))
        .map(str::to_owned)
}

fn init_args(payload: &Value) -> Result<Value, String> {
    let deployment = deployment_json()?;
    Ok(json!({
        "wallet_path": wallet_path(),
        "sequencer_url": sequencer_url(),
        "program_id_hex": required_str(&deployment, "program_id")?,
        "airdrop_id": hex_array(required_str(payload, "airdrop_id")?)?,
        "token_id": hex_array(required_str(payload, "token_id")?)?,
        "merkle_root": hex_array(required_str(payload, "merkle_root")?)?,
        "tree_depth": payload.get("tree_depth").and_then(Value::as_u64).unwrap_or(20),
        "bucket_table_hash": hex_array(required_str(payload, "bucket_table_hash")?)?,
        "bucket_table": payload.get("bucket_table").cloned().ok_or("missing bucket_table")?,
        "image_id": hex_array(required_str(&deployment, "method_image_id_hex")?)?,
        "expiry_unix": payload.get("expiry_unix").and_then(Value::as_i64).ok_or("missing expiry_unix")?,
        "recovery_address": hex_array(required_str(payload, "recovery_address")?)?,
        "now_unix": now_unix(),
        "distributor": account_id_arg(required_str(payload, "distributor")?)?,
    }))
}

fn fund_args(payload: &Value) -> Result<Value, String> {
    let deployment = deployment_json()?;
    let state = state_json()?;
    Ok(json!({
        "wallet_path": wallet_path(),
        "sequencer_url": sequencer_url(),
        "program_id_hex": required_str(&deployment, "program_id")?,
        "airdrop_id": hex_array(required_str(payload, "airdrop_id")?)?,
        "amount": payload.get("amount").and_then(Value::as_u64).ok_or("missing amount")?,
        "now_unix": now_unix(),
        "distributor": account_id_arg(required_str(&state, "distributor")?)?,
    }))
}

fn claim_args(payload: &Value) -> Result<Value, String> {
    let deployment = deployment_json()?;
    let state = state_json()?;
    let journal = payload.get("journal");
    let serialized_lez_tx = payload
        .get("serialized_lez_tx")
        .and_then(Value::as_array)
        .filter(|bytes| !bytes.is_empty())
        .ok_or("missing serialized_lez_tx")?;
    let tx = serialized_tx_json(serialized_lez_tx)?;
    let receipt_bytes = payload
        .get("receipt_bytes")
        .cloned()
        .or_else(|| tx.get("receipt_bytes").cloned())
        .ok_or("missing receipt_bytes")?;
    let mut args = json!({
        "wallet_path": wallet_path(),
        "sequencer_url": sequencer_url(),
        "program_id_hex": required_str(&deployment, "program_id")?,
        "airdrop_id": tx.get("airdrop_id").cloned().or_else(|| journal.and_then(|value| value.get("airdrop_id")).cloned()).ok_or("missing claim airdrop_id")?,
        "nullifier": tx.get("nullifier").cloned().or_else(|| journal.and_then(|value| value.get("nullifier")).cloned()).ok_or("missing claim nullifier")?,
        "receipt_bytes": receipt_bytes,
        "now_unix": tx.get("now_unix").and_then(Value::as_i64).unwrap_or_else(now_unix),
        "recipient": account_id_arg(required_str(&tx, "recipient")?)?,
        "distributor": account_id_arg(required_str(&state, "distributor")?)?,
    });
    if let (Some(npk), Some(vpk)) = (
        tx.get("recipient_npk").and_then(Value::as_str),
        tx.get("recipient_vpk").and_then(Value::as_str),
    ) {
        args["recipient_npk"] = json!(npk);
        args["recipient_vpk"] = json!(vpk);
    }
    if let Some(private_claim) = tx.get("private_claim") {
        args["private_claim"] = private_claim.clone();
        for field in [
            "bucket_id",
            "claim_destination_commitment",
            "claimant_address",
            "salt",
            "claim_sig",
            "merkle_siblings",
            "merkle_path_is_right",
        ] {
            args[field] = private_claim
                .get(field)
                .cloned()
                .ok_or_else(|| format!("missing private_claim.{field}"))?;
        }
    }
    if let Some(settlement) = payload.get("token_settlement") {
        args["token_settlement"] = settlement.clone();
    }
    Ok(args)
}

fn close_args(payload: &Value) -> Result<Value, String> {
    let deployment = deployment_json()?;
    let state = state_json()?;
    let airdrop_id = match payload.get("airdrop_id") {
        Some(value) if value.is_string() => hex_array(required_str(payload, "airdrop_id")?)?,
        Some(value) => value.clone(),
        None => hex_array(required_str(&state, "airdrop_id")?)?,
    };
    let recovery = payload
        .get("recovery_address")
        .and_then(Value::as_str)
        .unwrap_or(required_str(&state, "recovery_address")?);
    let distributor = payload
        .get("distributor")
        .and_then(Value::as_str)
        .unwrap_or(required_str(&state, "distributor")?);
    Ok(json!({
        "wallet_path": wallet_path(),
        "sequencer_url": sequencer_url(),
        "program_id_hex": required_str(&deployment, "program_id")?,
        "airdrop_id": airdrop_id,
        "recovery": account_id_arg(recovery)?,
        "distributor": account_id_arg(distributor)?,
    }))
}

fn call_generated(op: &str, args: &Value) -> Result<Value, String> {
    let body = args.to_string();
    let c_body = CString::new(body).map_err(|_| "args contain NUL byte")?;
    let ptr = match op {
        "init" => generated::distributionx_init_airdrop(c_body.as_ptr()),
        "fund" => generated::distributionx_fund(c_body.as_ptr()),
        "claim" => generated::distributionx_claim(c_body.as_ptr()),
        "claim_private" => generated::distributionx_claim_private(c_body.as_ptr()),
        "close" => generated::distributionx_close(c_body.as_ptr()),
        _ => return Err(format!("unknown generated op: {op}")),
    };
    if ptr.is_null() {
        return Err("generated call returned null".to_owned());
    }
    let text = unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map_err(|e| format!("generated UTF-8: {e}"))?
        .to_owned();
    generated::distributionx_free_string(ptr);
    let parsed: Value = serde_json::from_str(&text).map_err(|e| format!("generated JSON: {e}; {text}"))?;
    if parsed.get("success").and_then(Value::as_bool) == Some(true) {
        Ok(parsed)
    } else {
        Err(format!("generated submit failed: {parsed}"))
    }
}

fn serialized_tx_json(serialized_lez_tx: &[Value]) -> Result<Value, String> {
    let bytes = serialized_lez_tx
        .iter()
        .map(|value| {
            value
                .as_u64()
                .filter(|byte| *byte <= u8::MAX as u64)
                .map(|byte| byte as u8)
                .ok_or("serialized_lez_tx must be bytes")
        })
        .collect::<Result<Vec<_>, _>>()?;
    serde_json::from_slice(&bytes).map_err(|e| format!("serialized_lez_tx JSON: {e}"))
}

fn deployment_json() -> Result<Value, String> {
    let path = state_dir().join("deployment.json");
    serde_json::from_slice(&std::fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?)
        .map_err(|e| format!("deployment JSON: {e}"))
}

fn state_json() -> Result<Value, String> {
    let path = state_dir().join("state.json");
    serde_json::from_slice(&std::fs::read(&path).map_err(|e| format!("read {}: {e}", path.display()))?)
        .map_err(|e| format!("state JSON: {e}"))
}

fn state_dir() -> PathBuf {
    std::env::var("DISTRIBUTIONX_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("target/distributionx-testnet"))
}

fn wallet_path() -> String {
    std::env::var("NSSA_WALLET_HOME_DIR").unwrap_or_else(|_| ".scaffold/wallet".to_owned())
}

fn sequencer_url() -> String {
    std::env::var("LEZ_RPC_URL").unwrap_or_else(|_| "http://127.0.0.1:3040".to_owned())
}

fn required_str<'a>(value: &'a Value, field: &str) -> Result<&'a str, String> {
    value
        .get(field)
        .and_then(Value::as_str)
        .filter(|text| !text.trim().is_empty())
        .ok_or_else(|| format!("missing {field}"))
}

fn account_id_arg(value: &str) -> Result<String, String> {
    let trimmed = value.trim();
    if let Some((prefix, rest)) = trimmed.split_once('/') {
        if prefix == "Public" || prefix == "Private" {
            return Ok(rest.to_owned());
        }
    }
    if trimmed.len() == 64 && trimmed.chars().all(|ch| ch.is_ascii_hexdigit()) {
        return Ok(trimmed.to_owned());
    }
    Ok(trimmed.to_owned())
}

fn parse_account_id(value: &str) -> Result<AccountId, String> {
    let normalized = account_id_arg(value)?;
    if normalized.len() == 64 && normalized.chars().all(|ch| ch.is_ascii_hexdigit()) {
        let bytes = hex::decode(&normalized).map_err(|e| format!("account id hex {value}: {e}"))?;
        return Ok(AccountId::new(fixed_vec::<32>(bytes)?));
    }
    normalized
        .parse()
        .map_err(|e| format!("account id {value}: {e}"))
}

fn parse_program_id_hex(value: &str) -> Result<ProgramId, String> {
    let bytes = hex::decode(value.trim_start_matches("0x")).map_err(|e| format!("program id: {e}"))?;
    if bytes.len() != 32 {
        return Err(format!("program id must be 32 bytes, got {}", bytes.len()));
    }
    let mut out = [0u32; 8];
    for (index, chunk) in bytes.chunks_exact(4).enumerate() {
        out[index] = u32::from_le_bytes(chunk.try_into().expect("chunk length"));
    }
    Ok(out)
}

fn compute_pda_with_program(program_id: &ProgramId, seeds: &[&[u8]]) -> Result<AccountId, String> {
    Ok(AccountId::from((program_id, &PdaSeed::new(pda_seed_bytes(seeds)?))))
}

fn pda_seed_bytes(seeds: &[&[u8]]) -> Result<[u8; 32], String> {
    if seeds.is_empty() {
        return Err("PDA requires at least one seed".to_owned());
    }
    if seeds.len() == 1 {
        let len = seeds[0].len();
        if len > 32 {
            return Err(format!("PDA seed exceeds 32 bytes ({len})"));
        }
        let mut padded = [0u8; 32];
        padded[..len].copy_from_slice(&seeds[0][..len]);
        return Ok(padded);
    }
    let mut hasher = Sha256::new();
    for seed in seeds {
        let len = seed.len();
        if len > 32 {
            return Err(format!("PDA seed exceeds 32 bytes ({len})"));
        }
        let mut padded = [0u8; 32];
        padded[..len].copy_from_slice(&seed[..len]);
        hasher.update(padded);
    }
    Ok(hasher.finalize().into())
}

fn hex_array(value: &str) -> Result<Value, String> {
    let bytes = hex::decode(value.trim()).map_err(|e| format!("hex: {e}"))?;
    if bytes.len() != 32 {
        return Err(format!("expected 32 bytes, got {}", bytes.len()));
    }
    Ok(bytes_array(&fixed_vec::<32>(bytes)?))
}

fn parse_hex_32(value: &str) -> Result<[u8; 32], String> {
    let bytes = hex::decode(value.trim()).map_err(|e| format!("hex: {e}"))?;
    fixed_vec::<32>(bytes)
}

fn fixed_vec<const N: usize>(bytes: Vec<u8>) -> Result<[u8; N], String> {
    bytes
        .try_into()
        .map_err(|bytes: Vec<u8>| format!("expected {N} bytes, got {}", bytes.len()))
}

fn bytes_array<const N: usize>(bytes: &[u8; N]) -> Value {
    Value::Array(bytes.iter().map(|byte| json!(*byte)).collect())
}

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}
EOF

update_receipt_cu() {
  local response="$1"
  local receipts_dir="${DISTRIBUTIONX_RECEIPTS_DIR:-${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}/receipts}"
  local receipt_name="${op}"
  if [[ "${op}" == "init" ]]; then
    receipt_name="init_airdrop"
  fi
  local receipt_path="${receipts_dir}/${receipt_name}.json"
  local deployment_path="${DISTRIBUTIONX_STATE_DIR:-${ROOT}/target/distributionx-testnet}/deployment.json"
  local cu_log="${DISTRIBUTIONX_LEZ_CU_LOG:-/tmp/distributionx-standalone-sequencer-${UID:-$(id -u)}.log}"
  local adapter_stderr="${ADAPTER_STDERR:-}"

  [[ -f "${receipt_path}" && -f "${deployment_path}" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local tx_id program_id kind line cu source tmp
  tx_id="$(printf '%s\n' "${response}" | jq -r '.tx_id // empty' 2>/dev/null || true)"
  program_id="$(jq -r '.program_id // empty' "${deployment_path}" 2>/dev/null || true)"
  [[ -n "${tx_id}" && -n "${program_id}" ]] || return 0

  kind="public"
  line="$(
    {
      if [[ -n "${adapter_stderr}" && -f "${adapter_stderr}" ]]; then
        grep "DISTRIBUTIONX_LEZ_CU kind=${kind} program_id=${program_id} cycles=" "${adapter_stderr}" 2>/dev/null || true
      fi
      if [[ -f "${cu_log}" ]]; then
        grep "DISTRIBUTIONX_LEZ_CU kind=${kind} program_id=${program_id} cycles=" "${cu_log}" 2>/dev/null || true
      fi
    } | tail -n 1
  )"
  cu="${line##*cycles=}"
  [[ "${cu}" =~ ^[0-9]+$ ]] || return 0

  source="standalone-sequencer:${kind}"
  tmp="$(mktemp)"
  jq --argjson cu "${cu}" --arg source "${source}" \
    '.cu = $cu | .cu_source = $source' \
    "${receipt_path}" > "${tmp}" && mv "${tmp}" "${receipt_path}"
  rm -f "${tmp}"
}

ADAPTER_STDOUT="${ADAPTER_DIR}/stdout.log"
ADAPTER_STDERR="${ADAPTER_DIR}/stderr.log"
if cargo run -q --offline --manifest-path "${ADAPTER_DIR}/Cargo.toml" -- "${op}" >"${ADAPTER_STDOUT}" 2> >(tee "${ADAPTER_STDERR}" >&2); then
  ADAPTER_RESPONSE="$(tail -n 1 "${ADAPTER_STDOUT}")"
  update_receipt_cu "${ADAPTER_RESPONSE}"
  printf '%s\n' "${ADAPTER_RESPONSE}"
else
  cat "${ADAPTER_STDOUT}" >&2
  exit 1
fi
