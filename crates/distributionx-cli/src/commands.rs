use crate::args::{Cli, Command};
use distributionx_circuit::{ClaimJournal, ClaimWitness};
use distributionx_client::{
    build_distribution, compute_destination_commitment, prepare_claim,
    relayer::{RelayerSubmitRequest, RelayerSubmitResponse},
    DistributionDraft, DistributionXClientError, PreparedClaim, ShieldedDestinationPacket,
};
use distributionx_program::processor::{
    claim as program_claim, InitAirdropArgs, VerifiedClaimJournal,
};
use distributionx_program::state::Airdrop;
use distributionx_tree::{parse_csv, BundleV1};
use distributionx_wallet_ref::{DistributionXKeystore, EncryptedRowV1, InMemoryKeystore};
use example_program_deployment_methods::{
    DISTRIBUTIONX_METHODS_GUEST_ELF, DISTRIBUTIONX_METHODS_GUEST_ID,
};
use rand::RngCore;
use risc0_zkvm::{default_prover, ExecutorEnv, ProverOpts, Receipt};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::cmp::Reverse;
use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command as ProcessCommand, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_STATE_DIR: &str = "target/distributionx-testnet";
const DEFAULT_AIRDROP_NAME: &str = "demo-airdrop";
const DEFAULT_SAMPLE_CLAIM_AMOUNT: u64 = 100;

type CliResult<T> = Result<T, Box<dyn std::error::Error>>;

#[derive(Clone, Debug, Serialize, Deserialize)]
struct LocalAirdropState {
    name: String,
    airdrop_id: String,
    distributor: String,
    token_id: String,
    #[serde(default)]
    token_source_account: String,
    merkle_root: String,
    bucket_table_hash: String,
    bucket_table: Vec<u64>,
    expiry_unix: u64,
    recovery_address: String,
    total_funded: u64,
    total_claimed: u64,
    status: u8,
    nullifiers: BTreeSet<String>,
    bundle_path: String,
    deployment_mode: String,
    #[serde(default)]
    rpc_url: String,
    #[serde(default)]
    recipient_count: usize,
    #[serde(default)]
    last_tx_id: Option<String>,
    #[serde(default)]
    updated_at_unix: u64,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct AirdropRegistry {
    airdrops: Vec<AirdropRegistryEntry>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct AirdropRegistryEntry {
    name: String,
    airdrop_id: String,
    distributor: String,
    token_id: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    token_source_account: String,
    merkle_root: String,
    bucket_table_hash: String,
    eligible_count: usize,
    total_funded: u64,
    total_claimed: u64,
    expiry_unix: u64,
    recovery_address: String,
    status: String,
    state_path: String,
    bundle_path: String,
    deployment_mode: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    last_tx_id: Option<String>,
    updated_at_unix: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct BundleFile {
    version: u8,
    airdrop_id: String,
    bucket_table_hash: String,
    merkle_root: String,
    encrypted_rows: Vec<EncryptedRowFile>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct EncryptedRowFile {
    version: u8,
    row_index_le: String,
    ephemeral_x25519_pk: String,
    leaf: String,
    ciphertext_plus_tag: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ProofFile {
    proof_mode: String,
    risc0_dev_mode: String,
    risc0_real_proof: String,
    airdrop_id: String,
    amount_bucket: u8,
    receipt_bytes: String,
    journal: JournalFile,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ClaimTxFile {
    recipient: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    recipient_npk: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    recipient_vpk: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    private_claim: Option<PrivateClaimTxFile>,
    airdrop_id: [u8; 32],
    nullifier: [u8; 32],
    receipt_bytes: Vec<u8>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct PrivateClaimTxFile {
    bucket_id: u8,
    claim_destination_commitment: [u8; 32],
    claimant_address: [u8; 32],
    salt: [u8; 32],
    claim_sig: Vec<u8>,
    merkle_siblings: Vec<[u8; 32]>,
    merkle_path_is_right: Vec<bool>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct JournalFile {
    airdrop_id: String,
    merkle_root: String,
    bucket_id: u8,
    nullifier: String,
    claim_destination_commitment: String,
}

struct CheckedClaim {
    state: LocalAirdropState,
    prepared: PreparedClaim,
    amount: u64,
}

#[derive(Clone, Debug, Serialize)]
struct TokenSettlementRequest {
    token_id: String,
    source_account: String,
    recipient_account: String,
    amount: u64,
}

pub fn run(cli: Cli) {
    if let Err(err) = run_inner(cli) {
        eprintln!("{}", plain_error(&err.to_string()));
        std::process::exit(1);
    }
}

fn run_inner(cli: Cli) -> CliResult<()> {
    match cli.command {
        Command::Init {
            csv,
            distributor,
            token,
            token_source_account,
            rpc,
            expiry,
            recovery,
        } => init(
            &csv,
            &distributor,
            &token,
            token_source_account.as_deref(),
            &rpc,
            expiry,
            &recovery,
        ),
        Command::Fund { airdrop, amount } => fund(&airdrop, amount),
        Command::QueryTokenBalance {
            rpc,
            account,
            token,
        } => query_token_balance(&rpc, &account, &token),
        Command::Prove {
            airdrop,
            bundle,
            wallet,
            destination_packet,
            claim_destination_commitment,
        } => {
            let destination =
                resolve_claim_destination(destination_packet, claim_destination_commitment)?;
            prove(
                &airdrop,
                &bundle,
                &wallet,
                &destination.commitment,
                destination.packet.as_ref(),
            )
        }
        Command::PrepareClaimTx {
            airdrop,
            bundle,
            wallet,
            proof,
            destination_packet,
            claim_destination_commitment,
            out,
        } => prepare_claim_tx(
            &airdrop,
            &bundle,
            &wallet,
            proof,
            destination_packet,
            claim_destination_commitment,
            out,
        ),
        Command::CheckEligibility {
            airdrop,
            bundle,
            wallet,
            destination_packet,
            claim_destination_commitment,
        } => check_eligibility(
            &airdrop,
            &bundle,
            &wallet,
            destination_packet,
            claim_destination_commitment,
        ),
        Command::Claim {
            airdrop,
            proof,
            relayer,
            serialized_lez_tx,
        } => claim(&airdrop, &proof, &relayer, &serialized_lez_tx),
        Command::Close { airdrop } => close(&airdrop),
        Command::Verify { airdrop, proof } => verify(&airdrop, &proof),
        Command::Attest { airdrop } => attest(&airdrop),
        Command::InspectDestination { destination_packet } => {
            inspect_destination(Path::new(&destination_packet))
        }
        Command::InspectCsv { csv } => inspect_csv(Path::new(&csv)),
        Command::PadCsv {
            input,
            out,
            min_per_bucket,
            decoy_seed_label,
        } => pad_csv(
            Path::new(&input),
            Path::new(&out),
            min_per_bucket,
            &decoy_seed_label,
        ),
        Command::CreateWallet { out_dir } => create_wallet(out_dir.as_deref().map(Path::new)),
        Command::WalletPubkey { wallet } => wallet_pubkey(Path::new(&wallet)),
        Command::SetWallet { from, to } => set_wallet(Path::new(&from), Path::new(&to)),
        Command::TokenId { name } => token_id(&name),
        Command::MintToken {
            name,
            total_supply,
            offline,
        } => mint_token(&name, total_supply, offline),
        Command::MethodId => method_id(),
        Command::ListAirdrops => list_airdrops(),
        Command::SampleFixture { out_dir, claimants } => {
            sample_fixture(Path::new(&out_dir), claimants)
        }
    }
}

fn init(
    csv: &str,
    distributor: &str,
    token: &str,
    token_source_account: Option<&str>,
    rpc: &str,
    expiry: u64,
    recovery: &str,
) -> CliResult<()> {
    if !(rpc.starts_with("http://") || rpc.starts_with("https://")) {
        return Err(boxed_err("E_TESTNET_RPC_REQUIRED"));
    }
    let state_dir = state_dir();
    fs::create_dir_all(&state_dir)?;
    let csv_text = fs::read_to_string(csv)?;
    let token_id = parse_id(token)?;
    let token_source_account = token_source_account
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .or_else(|| {
            std::env::var("DISTRIBUTIONX_TOKEN_SOURCE_ACCOUNT")
                .ok()
                .map(|value| value.trim().to_owned())
                .filter(|value| !value.is_empty())
        })
        .unwrap_or_default();
    if !token_source_account.is_empty() {
        parse_id(&token_source_account)?;
    }
    let recovery_address = parse_id(recovery)?;
    let distributor = parse_id(distributor)?;
    let airdrop_name = airdrop_name();
    let draft = DistributionDraft::new(&airdrop_name, distributor)?;
    let built = build_distribution(
        draft,
        &csv_text,
        token_id,
        [0; 32],
        expiry,
        recovery_address,
        1,
    )?;
    let bundle_path = state_dir.join("bundle.json");
    write_json(&bundle_path, &BundleFile::from_bundle(&built.bundle))?;

    // Submit the init transaction. Requires DISTRIBUTIONX_INIT_SUBMIT_COMMAND for all RPC types.
    let init_payload = serde_json::json!({
        "kind": "distributionx-init",
        "airdrop_id": hex::encode(built.airdrop_id),
        "distributor": hex::encode(distributor),
        "token_id": hex::encode(token_id),
        "token_source_account": token_source_account.clone(),
        "merkle_root": hex::encode(built.bundle.merkle_root),
        "bucket_table_hash": hex::encode(built.bundle.bucket_table_hash),
        "bucket_table": built.bucket_table.clone(),
        "expiry_unix": expiry,
        "recovery_address": hex::encode(recovery_address),
        "rpc_url": rpc,
    });
    let init_tx_id = submit_signed_tx(
        "init",
        "DISTRIBUTIONX_INIT_SUBMIT_COMMAND",
        "E_DISTRIBUTIONX_INIT_SUBMIT_COMMAND_REQUIRED",
        &init_payload,
        rpc,
    )?;

    let state = LocalAirdropState {
        name: airdrop_name,
        airdrop_id: hex::encode(built.airdrop_id),
        distributor: hex::encode(distributor),
        token_id: hex::encode(token_id),
        token_source_account,
        merkle_root: hex::encode(built.bundle.merkle_root),
        bucket_table_hash: hex::encode(built.bundle.bucket_table_hash),
        bucket_table: built.bucket_table,
        expiry_unix: expiry,
        recovery_address: hex::encode(recovery_address),
        total_funded: 0,
        total_claimed: 0,
        status: 0,
        nullifiers: BTreeSet::new(),
        bundle_path: bundle_path.display().to_string(),
        deployment_mode: format!("testnet rpc={rpc}"),
        rpc_url: rpc.to_owned(),
        recipient_count: built.bundle.encrypted_rows.len(),
        last_tx_id: Some(init_tx_id.clone()),
        updated_at_unix: now_unix(),
    };
    save_state(&state)?;
    upsert_registry(&state)?;
    println!(
        "{}",
        serde_json::json!({
            "status": "INIT_OK",
            "airdrop": state.name,
            "airdrop_id": state.airdrop_id,
            "bundle": state.bundle_path,
            "token_id": state.token_id,
            "token_source_account": state.token_source_account,
            "recipient_count": built.bundle.encrypted_rows.len(),
            "tx_id": init_tx_id
        })
    );
    Ok(())
}

fn fund(airdrop: &str, amount: u64) -> CliResult<()> {
    let mut state = load_state_for(airdrop)?;
    ensure_airdrop(&state, airdrop)?;
    // Bind fund's RPC to the one init recorded so a stale LEZ_RPC_URL env can't
    // silently downgrade a testnet airdrop's fund tx to localnet semantics.
    let rpc = if !state.rpc_url.is_empty() {
        state.rpc_url.clone()
    } else if let Some(rest) = state.deployment_mode.strip_prefix("testnet rpc=") {
        rest.to_owned()
    } else {
        std::env::var("LEZ_RPC_URL").unwrap_or_default()
    };
    let env_rpc = std::env::var("LEZ_RPC_URL").unwrap_or_default();
    if !env_rpc.is_empty() && env_rpc != rpc {
        return Err(boxed_err("E_FUND_RPC_MISMATCH"));
    }
    let fund_payload = serde_json::json!({
        "kind": "distributionx-fund",
        "airdrop_id": state.airdrop_id,
        "airdrop": state.name,
        "amount": amount,
        "token_id": state.token_id,
        "rpc_url": rpc,
    });
    let fund_tx_id = submit_signed_tx(
        "fund",
        "DISTRIBUTIONX_FUND_SUBMIT_COMMAND",
        "E_DISTRIBUTIONX_FUND_SUBMIT_COMMAND_REQUIRED",
        &fund_payload,
        &rpc,
    )?;
    state.total_funded = state
        .total_funded
        .checked_add(amount)
        .ok_or_else(|| boxed_err("CLI_OVERFLOW"))?;
    state.last_tx_id = Some(fund_tx_id.clone());
    state.updated_at_unix = now_unix();
    save_state(&state)?;
    upsert_registry(&state)?;
    println!(
        "{}",
        serde_json::json!({
            "status": "FUND_OK",
            "airdrop": state.name,
            "amount": amount,
            "total_funded": state.total_funded,
            "tx_id": fund_tx_id
        })
    );
    Ok(())
}

fn query_token_balance(rpc_url: &str, account: &str, token: &str) -> CliResult<()> {
    match query_token_balance_inner(rpc_url, account, token) {
        Ok(response) => println!("{response}"),
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "QUERY_BALANCE_ERROR",
                    "error": err.to_string()
                })
            );
        }
    }
    Ok(())
}

fn query_token_balance_inner(
    rpc_url: &str,
    account: &str,
    token: &str,
) -> CliResult<serde_json::Value> {
    parse_id(account)?;
    parse_id(token)?;
    let payload = serde_json::json!({
        "op": "query",
        "wallet_path": default_wallet_path(),
        "sequencer_url": rpc_url,
        "account": account,
        "token": token,
    });
    run_local_token_script(&payload, "query")
}

fn prove(
    airdrop: &str,
    bundle: &str,
    wallet: &str,
    claim_destination_commitment: &[u8; 32],
    destination_packet: Option<&ShieldedDestinationPacket>,
) -> CliResult<()> {
    let checked = prepare_checked_claim(airdrop, bundle, wallet, claim_destination_commitment)?;
    let prepared = checked.prepared;

    let risc0_dev_mode = std::env::var("RISC0_DEV_MODE").unwrap_or_else(|_| "unset".to_owned());

    let receipt_bytes = generate_risc0_receipt(&prepared.proof.journal, &prepared.witness)
        .map_err(|err| boxed_err(format!("E_RISC0_PROVE:{err}")))?;

    let proof = ProofFile {
        proof_mode: "risc0-zkvm-receipt".to_owned(),
        risc0_dev_mode,
        risc0_real_proof: "OK".to_owned(),
        airdrop_id: hex::encode(prepared.proof.journal.airdrop_id),
        amount_bucket: prepared.amount_bucket,
        receipt_bytes: hex::encode(&receipt_bytes),
        journal: JournalFile::from_journal(&prepared.proof.journal),
    };
    let proof_path = state_dir().join("proof.json");
    write_json(&proof_path, &proof)?;
    let claim_tx_path = serialized_lez_tx_path();
    write_claim_tx(&prepared, Some(&proof), destination_packet, &claim_tx_path)?;
    println!("{}", prove_log_line(&proof.risc0_dev_mode));
    println!(
        "{}",
        serde_json::json!({
            "status": "PROVE_LOCAL_OK",
            "proof": proof_path.display().to_string(),
            "serialized_lez_tx": claim_tx_path.display().to_string(),
            "proof_mode": proof.proof_mode,
            "risc0_real_proof": proof.risc0_real_proof,
            "nullifier": proof.journal.nullifier,
            "claim_destination_commitment": proof.journal.claim_destination_commitment
        })
    );
    Ok(())
}

fn prepare_claim_tx(
    airdrop: &str,
    bundle: &str,
    wallet: &str,
    proof: Option<String>,
    destination_packet: Option<String>,
    claim_destination_commitment: Option<String>,
    out: Option<String>,
) -> CliResult<()> {
    let destination = resolve_claim_destination(destination_packet, claim_destination_commitment)?;
    let checked = prepare_checked_claim(airdrop, bundle, wallet, &destination.commitment)?;
    let proof = match proof {
        Some(path) => {
            let proof = read_proof(Path::new(&path))?;
            if checked.prepared.proof.journal != proof.to_journal()? {
                return Err(boxed_err("E_RECEIPT_JOURNAL_MISMATCH"));
            }
            Some(proof)
        }
        None => None,
    };
    let path = out
        .map(PathBuf::from)
        .unwrap_or_else(serialized_lez_tx_path);
    write_claim_tx(
        &checked.prepared,
        proof.as_ref(),
        destination.packet.as_ref(),
        &path,
    )?;
    println!(
        "{}",
        serde_json::json!({
            "status": "PREPARE_CLAIM_TX_OK",
            "serialized_lez_tx": path.display().to_string()
        })
    );
    Ok(())
}

fn check_eligibility(
    airdrop: &str,
    bundle: &str,
    wallet: &str,
    destination_packet: Option<String>,
    claim_destination_commitment: Option<String>,
) -> CliResult<()> {
    let result = resolve_claim_destination_commitment_for_check(
        destination_packet,
        claim_destination_commitment,
    )
    .and_then(|destination_commitment| {
        prepare_checked_claim(airdrop, bundle, wallet, &destination_commitment)
            .map(|checked| (destination_commitment, checked))
    });

    match result {
        Ok((destination_commitment, checked)) => {
            let journal = &checked.prepared.proof.journal;
            println!(
                "{}",
                serde_json::json!({
                    "status": "ELIGIBILITY_OK",
                    "eligible": true,
                    "airdrop": checked.state.name,
                    "airdrop_id": checked.state.airdrop_id,
                    "amount": checked.amount,
                    "amount_raw": checked.amount.to_string(),
                    "amount_bucket": checked.prepared.amount_bucket,
                    "nullifier": hex::encode(journal.nullifier),
                    "claim_destination_commitment": hex::encode(destination_commitment)
                })
            );
        }
        Err(err) => {
            let raw = err.to_string();
            let code = eligibility_error_code(&raw);
            println!(
                "{}",
                serde_json::json!({
                    "status": "ELIGIBILITY_REJECTED",
                    "eligible": false,
                    "error_code": code,
                    "error": eligibility_error_message(code, &raw),
                    "detail": raw
                })
            );
        }
    }
    Ok(())
}

fn prepare_checked_claim(
    airdrop: &str,
    bundle: &str,
    wallet: &str,
    claim_destination_commitment: &[u8; 32],
) -> CliResult<CheckedClaim> {
    let state = load_claim_state(airdrop)?;
    ensure_airdrop(&state, airdrop)?;
    let bundle = read_bundle_for_claim(Path::new(bundle))?;
    let seed = read_seed_for_claim(Path::new(wallet))?;
    let keystore = InMemoryKeystore::from_seed(seed)
        .map_err(|err| boxed_err(format!("E_WALLET_SEED_INVALID:{err}")))?;
    let prepared = prepare_claim(&keystore, &bundle, *claim_destination_commitment).map_err(
        |err| match err {
            DistributionXClientError::NoEligibleRow => boxed_err("E_WALLET_NOT_ELIGIBLE"),
            DistributionXClientError::InvalidDestinationCommitment => {
                boxed_err("E_DESTINATION_COMMITMENT_INVALID")
            }
            DistributionXClientError::InvalidDestinationPacket => {
                boxed_err("E_DESTINATION_PACKET_INVALID")
            }
            other => boxed_err(format!("E_CLAIM_PREPARE_FAILED:{other}")),
        },
    )?;
    if let Some(code) = pre_prove_rejection_code(
        &state.airdrop_id,
        prepared.proof.journal.airdrop_id,
        &state.nullifiers,
        prepared.proof.journal.nullifier,
    ) {
        return Err(boxed_err(code));
    }

    let verified_claim =
        VerifiedClaimJournal::from_verified_journal_unchecked(prepared.proof.journal.clone());
    let amount = program_claim(
        &state.to_airdrop()?,
        parse_hex_32(&state.airdrop_id)?,
        prepared.proof.journal.nullifier,
        &verified_claim,
        state.total_funded.saturating_sub(state.total_claimed),
    )
    .map_err(|err| boxed_err(format!("E_PROGRAM_{}", err.0)))?;

    Ok(CheckedClaim {
        state,
        prepared,
        amount,
    })
}

fn load_claim_state(airdrop: &str) -> CliResult<LocalAirdropState> {
    load_state_for(airdrop).map_err(|err| {
        let raw = err.to_string();
        if raw.contains("E_AIRDROP_ID_MISMATCH") {
            boxed_err("E_DISTRIBUTION_NOT_FOUND")
        } else {
            boxed_err(format!("E_DISTRIBUTION_STATE_INVALID:{raw}"))
        }
    })
}

fn read_bundle_for_claim(path: &Path) -> CliResult<BundleV1> {
    let bytes = fs::read(path).map_err(|err| {
        if err.kind() == std::io::ErrorKind::NotFound {
            boxed_err("E_BUNDLE_NOT_FOUND")
        } else {
            boxed_err(format!("E_BUNDLE_READ:{err}"))
        }
    })?;
    let file = serde_json::from_slice(&bytes)
        .map_err(|err| boxed_err(format!("E_BUNDLE_INVALID:{err}")))?;
    BundleFile::to_bundle(file).map_err(|err| boxed_err(format!("E_BUNDLE_INVALID:{err}")))
}

fn read_seed_for_claim(path: &Path) -> CliResult<[u8; 32]> {
    let raw = fs::read_to_string(path).map_err(|err| {
        if err.kind() == std::io::ErrorKind::NotFound {
            boxed_err("E_WALLET_SEED_NOT_FOUND")
        } else {
            boxed_err(format!("E_WALLET_SEED_READ:{err}"))
        }
    })?;
    parse_hex_32(raw.trim()).map_err(|err| boxed_err(format!("E_WALLET_SEED_INVALID:{err}")))
}

fn resolve_claim_destination_commitment_for_check(
    destination_packet: Option<String>,
    claim_destination_commitment: Option<String>,
) -> CliResult<[u8; 32]> {
    let selected =
        destination_packet.is_some() as u8 + claim_destination_commitment.is_some() as u8;
    if selected > 1 {
        return Err(boxed_err("E_DESTINATION_CONFLICT"));
    }
    if let Some(path) = destination_packet {
        let packet = read_destination_packet_for_claim(Path::new(&path))?;
        return Ok(compute_destination_commitment(&packet));
    }
    if let Some(value) = claim_destination_commitment {
        return parse_id(&value)
            .map_err(|err| boxed_err(format!("E_DESTINATION_COMMITMENT_INVALID:{err}")));
    }
    Err(boxed_err("E_MISSING_DESTINATION_COMMITMENT"))
}

fn read_destination_packet_for_claim(path: &Path) -> CliResult<ShieldedDestinationPacket> {
    let bytes = fs::read(path).map_err(|err| {
        if err.kind() == std::io::ErrorKind::NotFound {
            boxed_err("E_DESTINATION_PACKET_NOT_FOUND")
        } else {
            boxed_err(format!("E_DESTINATION_PACKET_READ:{err}"))
        }
    })?;
    ShieldedDestinationPacket::from_json_slice(&bytes)
        .map_err(|err| boxed_err(format!("E_DESTINATION_PACKET_INVALID:{err}")))
}

fn eligibility_error_code(raw: &str) -> &'static str {
    for code in [
        "E_ALREADY_CLAIMED",
        "E_AIRDROP_ID_MISMATCH",
        "E_BUNDLE_INVALID",
        "E_BUNDLE_NOT_FOUND",
        "E_CLAIM_PREPARE_FAILED",
        "E_DESTINATION_COMMITMENT_INVALID",
        "E_DESTINATION_CONFLICT",
        "E_DESTINATION_PACKET_INVALID",
        "E_DESTINATION_PACKET_NOT_FOUND",
        "E_DISTRIBUTION_NOT_FOUND",
        "E_DISTRIBUTION_STATE_INVALID",
        "E_MISSING_DESTINATION_COMMITMENT",
        "E_PROGRAM_1",
        "E_PROGRAM_2",
        "E_PROGRAM_3",
        "E_PROGRAM_4",
        "E_PROGRAM_7",
        "E_WALLET_NOT_ELIGIBLE",
        "E_WALLET_SEED_INVALID",
        "E_WALLET_SEED_NOT_FOUND",
    ] {
        if raw.contains(code) {
            return code;
        }
    }
    "E_ELIGIBILITY_CHECK_FAILED"
}

fn eligibility_error_message(code: &str, raw: &str) -> String {
    match code {
        "E_ALREADY_CLAIMED" => "This wallet has already claimed this distribution.",
        "E_AIRDROP_ID_MISMATCH" | "E_DISTRIBUTION_NOT_FOUND" => {
            "The selected distribution was not found or does not match this bundle."
        }
        "E_BUNDLE_INVALID" => "The selected bundle file is not a valid DistributionX bundle.",
        "E_BUNDLE_NOT_FOUND" => "The selected bundle file does not exist.",
        "E_DESTINATION_COMMITMENT_INVALID" => {
            "The destination commitment is not a valid 32-byte value."
        }
        "E_DESTINATION_CONFLICT" => {
            "Use either a destination packet or a destination commitment, not both."
        }
        "E_DESTINATION_PACKET_INVALID" => {
            "The destination packet is not a valid shielded destination file."
        }
        "E_DESTINATION_PACKET_NOT_FOUND" => "The destination packet file does not exist.",
        "E_DISTRIBUTION_STATE_INVALID" => "The selected distribution state could not be read.",
        "E_MISSING_DESTINATION_COMMITMENT" => "Load a destination packet before claiming.",
        "E_PROGRAM_1" => "This distribution is closed.",
        "E_PROGRAM_2" | "E_PROGRAM_3" => "The selected bundle does not match this distribution.",
        "E_PROGRAM_4" => "The selected bundle uses an unsupported claim amount bucket.",
        "E_PROGRAM_7" => "This distribution is not funded enough for this claim.",
        "E_WALLET_NOT_ELIGIBLE" => "This wallet is not eligible for the selected distribution.",
        "E_WALLET_SEED_INVALID" => "The selected wallet seed is not valid.",
        "E_WALLET_SEED_NOT_FOUND" => "Load a wallet seed before claiming.",
        "E_CLAIM_PREPARE_FAILED" => "The claim could not be prepared from the selected inputs.",
        _ => raw,
    }
    .to_owned()
}

struct ResolvedDestination {
    commitment: [u8; 32],
    packet: Option<ShieldedDestinationPacket>,
}

fn resolve_claim_destination(
    destination_packet: Option<String>,
    claim_destination_commitment: Option<String>,
) -> CliResult<ResolvedDestination> {
    let selected =
        destination_packet.is_some() as u8 + claim_destination_commitment.is_some() as u8;
    if selected > 1 {
        return Err(boxed_err("E_DESTINATION_CONFLICT"));
    }
    if let Some(path) = destination_packet {
        let packet = read_destination_packet(Path::new(&path))?;
        return Ok(ResolvedDestination {
            commitment: compute_destination_commitment(&packet),
            packet: Some(packet),
        });
    }
    if let Some(value) = claim_destination_commitment {
        return Ok(ResolvedDestination {
            commitment: parse_id(&value)?,
            packet: None,
        });
    }
    Err(boxed_err("E_MISSING_DESTINATION_COMMITMENT"))
}

fn generate_risc0_receipt(
    journal: &ClaimJournal,
    witness: &ClaimWitness,
) -> Result<Vec<u8>, String> {
    let env = ExecutorEnv::builder()
        .write(journal)
        .map_err(|e| format!("env write journal: {e}"))?
        .write(witness)
        .map_err(|e| format!("env write witness: {e}"))?
        .build()
        .map_err(|e| format!("env build: {e}"))?;
    let prover = default_prover();
    let receipt = prover
        .prove_with_opts(env, DISTRIBUTIONX_METHODS_GUEST_ELF, &ProverOpts::groth16())
        .map_err(|e| format!("prove: {e}"))?
        .receipt;
    bincode::serialize(&receipt).map_err(|e| format!("serialize: {e}"))
}

fn claim(airdrop: &str, proof: &str, relayer: &str, serialized_lez_tx: &str) -> CliResult<()> {
    let mut state = load_state_for(airdrop)?;
    ensure_airdrop(&state, airdrop)?;
    let claim_tx = read_claim_tx(Path::new(serialized_lez_tx))?;
    if let Some(private_claim) = claim_tx.private_claim.as_ref() {
        let expected_airdrop_id = parse_hex_32(&state.airdrop_id)?;
        if claim_tx.airdrop_id != expected_airdrop_id {
            return Err(boxed_err("E_AIRDROP_ID_MISMATCH"));
        }
        let nullifier_hex = hex::encode(claim_tx.nullifier);
        if state.nullifiers.contains(&nullifier_hex) {
            return Err(boxed_err("E_ALREADY_CLAIMED"));
        }
        if private_claim.claim_destination_commitment == [0u8; 32] {
            return Err(boxed_err("E_DESTINATION_COMMITMENT_INVALID"));
        }
        if private_claim.bucket_id as usize >= state.bucket_table.len() {
            return Err(boxed_err("E_PROGRAM_4"));
        }
        let amount = state.bucket_table[private_claim.bucket_id as usize];
        if amount > state.total_funded.saturating_sub(state.total_claimed) {
            return Err(boxed_err("E_PROGRAM_7"));
        }
        let token_settlement = token_settlement_for_claim(&state, &claim_tx.recipient, amount);
        let tx_id = submit_claim_to_testnet(
            None,
            relayer,
            Path::new(serialized_lez_tx),
            token_settlement.as_ref(),
        )?;
        state.total_claimed = state
            .total_claimed
            .checked_add(amount)
            .ok_or_else(|| boxed_err("CLI_OVERFLOW"))?;
        state.nullifiers.insert(nullifier_hex);
        state.last_tx_id = Some(tx_id.clone());
        state.updated_at_unix = now_unix();
        save_state(&state)?;
        upsert_registry(&state)?;
        println!(
            "{}",
            serde_json::json!({
                "status": "CLAIM_OK",
                "airdrop": state.name,
                "relayer": relayer,
                "amount": amount,
                "total_claimed": state.total_claimed,
                "tx_id": tx_id
            })
        );
        return Ok(());
    }

    let proof = read_proof(Path::new(proof))?;
    if proof.airdrop_id != state.airdrop_id {
        return Err(boxed_err("E_AIRDROP_ID_MISMATCH"));
    }
    if state.nullifiers.contains(&proof.journal.nullifier) {
        return Err(boxed_err("E_ALREADY_CLAIMED"));
    }
    let receipt_bytes =
        hex::decode(&proof.receipt_bytes).map_err(|e| boxed_err(format!("E_RECEIPT_HEX:{e}")))?;
    let verified_claim = VerifiedClaimJournal::from_risc0_receipt(&receipt_bytes)
        .map_err(|err| boxed_err(format!("E_PROGRAM_{}", err.0)))?;
    if *verified_claim.journal() != proof.to_journal()? {
        return Err(boxed_err("E_RECEIPT_JOURNAL_MISMATCH"));
    }
    let airdrop_model = state.to_airdrop()?;
    let amount = program_claim(
        &airdrop_model,
        parse_hex_32(&state.airdrop_id)?,
        parse_hex_32(&proof.journal.nullifier)?,
        &verified_claim,
        state.total_funded.saturating_sub(state.total_claimed),
    )
    .map_err(|err| boxed_err(format!("E_PROGRAM_{}", err.0)))?;
    let token_settlement = token_settlement_for_claim(&state, &claim_tx.recipient, amount);
    let tx_id = submit_claim_to_testnet(
        Some(&proof),
        relayer,
        Path::new(serialized_lez_tx),
        token_settlement.as_ref(),
    )?;
    state.total_claimed = state
        .total_claimed
        .checked_add(amount)
        .ok_or_else(|| boxed_err("CLI_OVERFLOW"))?;
    state.nullifiers.insert(proof.journal.nullifier.clone());
    state.last_tx_id = Some(tx_id.clone());
    state.updated_at_unix = now_unix();
    save_state(&state)?;
    upsert_registry(&state)?;
    println!(
        "{}",
        serde_json::json!({
            "status": "CLAIM_OK",
            "airdrop": state.name,
            "relayer": relayer,
            "amount": amount,
            "total_claimed": state.total_claimed,
            "tx_id": tx_id
        })
    );
    Ok(())
}

fn token_settlement_for_claim(
    state: &LocalAirdropState,
    recipient_account: &str,
    amount: u64,
) -> Option<TokenSettlementRequest> {
    if state.token_source_account.trim().is_empty() || amount == 0 {
        return None;
    }
    Some(TokenSettlementRequest {
        token_id: state.token_id.clone(),
        source_account: state.token_source_account.clone(),
        recipient_account: recipient_account.to_owned(),
        amount,
    })
}

fn verify(airdrop: &str, proof: &str) -> CliResult<()> {
    let state = load_state_for(airdrop)?;
    ensure_airdrop(&state, airdrop)?;
    let proof = read_proof(Path::new(proof))?;
    if proof.to_journal()?.airdrop_id != parse_hex_32(&state.airdrop_id)? {
        return Err(boxed_err("E_AIRDROP_ID_MISMATCH"));
    }
    let journal_from_receipt = verify_risc0_receipt(&proof)?;
    if journal_from_receipt != proof.to_journal()? {
        return Err(boxed_err("E_RECEIPT_JOURNAL_MISMATCH"));
    }
    println!(
        "{}",
        serde_json::json!({
            "status": "VERIFY_OK",
            "proof_mode": proof.proof_mode,
            "risc0_real_proof": proof.risc0_real_proof,
            "risc0_receipt_verify": "verified"
        })
    );
    Ok(())
}

fn close(airdrop: &str) -> CliResult<()> {
    let mut state = load_state_for(airdrop)?;
    ensure_airdrop(&state, airdrop)?;
    let close_tx_id = if std::env::var("DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND").is_ok() {
        let close_payload = serde_json::json!({
            "kind": "distributionx-close",
            "airdrop_id": state.airdrop_id,
            "airdrop": state.name,
            "distributor": state.distributor,
            "recovery_address": state.recovery_address,
            "rpc_url": state.rpc_url,
        });
        Some(submit_signed_tx(
            "close",
            "DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND",
            "E_DISTRIBUTIONX_CLOSE_SUBMIT_COMMAND_REQUIRED",
            &close_payload,
            &state.rpc_url,
        )?)
    } else {
        None
    };
    state.status = 1;
    if let Some(tx_id) = close_tx_id.clone() {
        state.last_tx_id = Some(tx_id);
    }
    state.updated_at_unix = now_unix();
    save_state(&state)?;
    upsert_registry(&state)?;
    println!(
        "{}",
        serde_json::json!({
            "status": "CLOSE_OK",
            "airdrop": state.name,
            "recovery_address": state.recovery_address,
            "tx_id": close_tx_id
        })
    );
    Ok(())
}

fn attest(airdrop: &str) -> CliResult<()> {
    let state = load_state_for(airdrop)?;
    ensure_airdrop(&state, airdrop)?;
    println!(
        "{}",
        serde_json::json!({
            "status": "ATTEST_OK",
            "airdrop_id": state.airdrop_id,
            "merkle_root": state.merkle_root,
            "bucket_table_hash": state.bucket_table_hash,
            "population_privacy_floor": 8
        })
    );
    Ok(())
}

fn inspect_destination(destination_packet: &Path) -> CliResult<()> {
    let packet = read_destination_packet(destination_packet)?;
    let commitment = compute_destination_commitment(&packet);
    println!(
        "{}",
        serde_json::json!({
            "status": "DESTINATION_PACKET_OK",
            "claim_destination_commitment": hex::encode(commitment)
        })
    );
    Ok(())
}

fn inspect_csv(csv_path: &Path) -> CliResult<()> {
    let raw = match fs::read_to_string(csv_path) {
        Ok(s) => s,
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "CSV_INVALID",
                    "error": format!("read failed: {err}")
                })
            );
            return Ok(());
        }
    };
    match parse_csv(&raw) {
        Ok(proposal) => {
            let total_amount: u64 = proposal.rows.iter().map(|r| r.raw_amount).sum();
            let preview: Vec<serde_json::Value> = proposal
                .rows
                .iter()
                .take(5)
                .map(|r| {
                    let address_hex = hex::encode(r.address);
                    let short = if address_hex.len() > 16 {
                        format!(
                            "{}...{}",
                            &address_hex[..8],
                            &address_hex[address_hex.len() - 8..]
                        )
                    } else {
                        address_hex.clone()
                    };
                    serde_json::json!({
                        "address": address_hex,
                        "address_short": short,
                        "raw_amount": r.raw_amount,
                        "bucket_id": r.bucket_id
                    })
                })
                .collect();
            let min_per_bucket = proposal
                .population_per_bucket
                .iter()
                .copied()
                .min()
                .unwrap_or(0);
            const RECOMMENDED_FLOOR: usize = 8;
            let warning = if min_per_bucket > 0 && min_per_bucket < RECOMMENDED_FLOOR {
                Some(format!(
                    "Smallest amount-bucket has {min_per_bucket} recipient(s); the documented privacy property (observer-unlinkability) holds with anonymity-set 1/k per bucket and is recommended at k>={RECOMMENDED_FLOOR}. Pad with `pad-csv --min-per-bucket {RECOMMENDED_FLOOR}` if you want the baseline."
                ))
            } else {
                None
            };
            println!(
                "{}",
                serde_json::json!({
                    "status": "CSV_OK",
                    "row_count": proposal.rows.len(),
                    "total_amount": total_amount,
                    "duplicate_count": 0,
                    "invalid_count": 0,
                    "bucket_table": proposal.bucket_table,
                    "population_per_bucket": proposal.population_per_bucket,
                    "min_per_bucket": min_per_bucket,
                    "recommended_min_per_bucket": RECOMMENDED_FLOOR,
                    "warning": warning,
                    "preview": preview
                })
            );
        }
        Err(err) => {
            let code = match err {
                distributionx_tree::DistributionXTreeError::CliAddrNonCanonical => {
                    "row format invalid"
                }
                distributionx_tree::DistributionXTreeError::CliDuplicateAddr => {
                    "duplicate recipient"
                }
                distributionx_tree::DistributionXTreeError::CliBucketOob => {
                    "amount or bucket count out of range"
                }
                distributionx_tree::DistributionXTreeError::CliPopulationCap => {
                    "more than 50,000 rows"
                }
                _ => "csv rejected",
            };
            println!(
                "{}",
                serde_json::json!({
                    "status": "CSV_INVALID",
                    "error": code
                })
            );
        }
    }
    Ok(())
}

fn pad_csv(
    input_path: &Path,
    out_path: &Path,
    min_per_bucket: usize,
    decoy_seed_label: &str,
) -> CliResult<()> {
    let raw = match fs::read_to_string(input_path) {
        Ok(s) => s,
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "PAD_CSV_INVALID",
                    "error": format!("read failed: {err}")
                })
            );
            return Ok(());
        }
    };
    let mut lines = raw.lines();
    let header = lines.next().unwrap_or("");
    if header != "address,raw_amount" {
        println!(
            "{}",
            serde_json::json!({
                "status": "PAD_CSV_INVALID",
                "error": "input csv must start with `address,raw_amount` header"
            })
        );
        return Ok(());
    }

    let mut existing: Vec<(String, u64)> = Vec::new();
    let mut existing_addrs = BTreeSet::new();
    for line in lines {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let (addr, amount) = match trimmed.split_once(',') {
            Some(parts) => parts,
            None => {
                println!(
                    "{}",
                    serde_json::json!({
                        "status": "PAD_CSV_INVALID",
                        "error": format!("malformed row: {trimmed}")
                    })
                );
                return Ok(());
            }
        };
        let amount: u64 = match amount.parse() {
            Ok(v) => v,
            Err(_) => {
                println!(
                    "{}",
                    serde_json::json!({
                        "status": "PAD_CSV_INVALID",
                        "error": format!("invalid amount on row: {trimmed}")
                    })
                );
                return Ok(());
            }
        };
        existing_addrs.insert(addr.to_owned());
        existing.push((addr.to_owned(), amount));
    }

    // Bucket by amount, count gaps to k-anonymity floor.
    let mut bucket_counts: std::collections::BTreeMap<u64, usize> =
        std::collections::BTreeMap::new();
    for (_, amount) in &existing {
        *bucket_counts.entry(*amount).or_default() += 1;
    }

    let mut decoy_index: u32 = 0;
    let mut padded_lines: Vec<String> = existing.iter().map(|(a, v)| format!("{a},{v}")).collect();
    let mut decoys_added: u64 = 0;

    for (amount, count) in &bucket_counts {
        if *count >= min_per_bucket {
            continue;
        }
        let needed = min_per_bucket - count;
        for _ in 0..needed {
            // Deterministic decoy pubkey: SHA256(label || index) -> 32 bytes
            // (collision-resistant; never controlled by anyone — funds locked at decoy).
            let decoy_addr = loop {
                let mut hasher = Sha256::new();
                hasher.update(decoy_seed_label.as_bytes());
                hasher.update(decoy_index.to_le_bytes());
                let digest = hasher.finalize();
                let hex_addr = hex::encode(digest);
                decoy_index += 1;
                if !existing_addrs.contains(&hex_addr) {
                    existing_addrs.insert(hex_addr.clone());
                    break hex_addr;
                }
            };
            padded_lines.push(format!("{decoy_addr},{amount}"));
            decoys_added += 1;
        }
    }

    let mut padded = String::from("address,raw_amount\n");
    for line in &padded_lines {
        padded.push_str(line);
        padded.push('\n');
    }

    if let Some(parent) = out_path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    fs::write(out_path, padded)?;
    println!(
        "{}",
        serde_json::json!({
            "status": "PAD_CSV_OK",
            "input_path": input_path.display().to_string(),
            "out_path": out_path.display().to_string(),
            "row_count": existing.len() + decoys_added as usize,
            "real_count": existing.len(),
            "decoys_added": decoys_added,
            "min_per_bucket": min_per_bucket
        })
    );
    Ok(())
}

fn create_wallet(out_dir: Option<&Path>) -> CliResult<()> {
    let mut seed = [0u8; 32];
    let mut rng = rand::rngs::OsRng;
    rng.fill_bytes(&mut seed);
    let keystore = InMemoryKeystore::from_seed(seed)?;
    let pubkey_hex = hex::encode(keystore.public_ed25519());
    let wallet_seed_path = if let Some(out_dir) = out_dir {
        fs::create_dir_all(out_dir)?;
        let path = out_dir.join("wallet.seed");
        fs::write(&path, hex::encode(seed))?;
        Some(path.display().to_string())
    } else {
        None
    };
    println!(
        "{}",
        serde_json::json!({
            "status": "CREATE_WALLET_OK",
            "account": format!("Public/{pubkey_hex}"),
            "wallet_seed_path": wallet_seed_path
        })
    );
    Ok(())
}

fn wallet_pubkey(wallet_path: &Path) -> CliResult<()> {
    let seed = match read_seed(wallet_path) {
        Ok(s) => s,
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "WALLET_PUBKEY_INVALID",
                    "error": format!("read failed: {err}")
                })
            );
            return Ok(());
        }
    };
    let keystore = match InMemoryKeystore::from_seed(seed) {
        Ok(ks) => ks,
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "WALLET_PUBKEY_INVALID",
                    "error": format!("keystore: {err}")
                })
            );
            return Ok(());
        }
    };
    let pubkey_hex = hex::encode(keystore.public_ed25519());
    println!(
        "{}",
        serde_json::json!({
            "status": "WALLET_PUBKEY_OK",
            "pubkey": pubkey_hex,
            "pubkey_lez": format!("Public/{pubkey_hex}")
        })
    );
    Ok(())
}

fn set_wallet(from: &Path, to: &Path) -> CliResult<()> {
    // Validate the source can be parsed as a 32-byte hex seed before copying — this prevents
    // the UI from accepting an arbitrary file as a wallet seed.
    let seed = match read_seed(from) {
        Ok(s) => s,
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "SET_WALLET_INVALID",
                    "error": format!("source not a valid seed: {err}")
                })
            );
            return Ok(());
        }
    };
    let keystore = match InMemoryKeystore::from_seed(seed) {
        Ok(ks) => ks,
        Err(err) => {
            println!(
                "{}",
                serde_json::json!({
                    "status": "SET_WALLET_INVALID",
                    "error": format!("keystore: {err}")
                })
            );
            return Ok(());
        }
    };
    if let Some(parent) = to.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    fs::write(to, hex::encode(seed))?;
    let pubkey_hex = hex::encode(keystore.public_ed25519());
    println!(
        "{}",
        serde_json::json!({
            "status": "SET_WALLET_OK",
            "from": from.display().to_string(),
            "to": to.display().to_string(),
            "pubkey": pubkey_hex,
            "pubkey_lez": format!("Public/{pubkey_hex}")
        })
    );
    Ok(())
}

fn token_id(name: &str) -> CliResult<()> {
    let token_id = format!(
        "Public/{}",
        hex::encode(parse_id(&format!("Public/{name}"))?)
    );
    println!(
        "{}",
        serde_json::json!({
            "status": "TOKEN_ID_OK",
            "token_id": token_id,
            "name": name,
            "registered": false,
            "note": "offline-derived label; not registered with the LEZ token program. Run `mint-token` for a real token definition."
        })
    );
    Ok(())
}

fn mint_token(name: &str, total_supply: u64, offline: bool) -> CliResult<()> {
    if offline {
        let token_id = format!(
            "Public/{}",
            hex::encode(parse_id(&format!("Public/{name}"))?)
        );
        println!(
            "{}",
            serde_json::json!({
                "status": "TOKEN_MINTED_OFFLINE",
                "token_id": token_id,
                "name": name,
                "total_supply": total_supply,
                "registered": false,
                "note": "offline-only id; the LEZ token program was not contacted"
            })
        );
        return Ok(());
    }

    let wallet_path = default_wallet_path();
    let sequencer_url = std::env::var("LEZ_RPC_URL").map_err(|_| {
        boxed_err(
            "E_DISTRIBUTIONX_LEZ_RPC_URL_REQUIRED: set LEZ_RPC_URL or pass --offline".to_string(),
        )
    })?;

    let payload = serde_json::json!({
        "op": "mint",
        "wallet_path": wallet_path,
        "sequencer_url": sequencer_url,
        "name": name,
        "total_supply": total_supply,
    });

    let response = run_local_token_script(&payload, "mint")?;
    println!("{response}");
    Ok(())
}

fn run_local_token_script(
    payload: &serde_json::Value,
    label: &str,
) -> CliResult<serde_json::Value> {
    let script = if std::env::var("DISTRIBUTIONX_LOCAL_TOKEN_SCRIPT").is_ok() {
        resolve_helper_script("DISTRIBUTIONX_LOCAL_TOKEN_SCRIPT", "local-token-mint.sh")?
    } else {
        resolve_helper_script(
            "DISTRIBUTIONX_LOCAL_TOKEN_MINT_SCRIPT",
            "local-token-mint.sh",
        )?
    };
    let mut child = ProcessCommand::new("bash")
        .arg(&script)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(|err| {
            boxed_err(format!(
                "failed to launch {script}: {err}",
                script = script.display()
            ))
        })?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(payload.to_string().as_bytes())
            .map_err(|err| {
                boxed_err(format!(
                    "write {label} payload to local-token-mint.sh: {err}"
                ))
            })?;
    }

    let output = child
        .wait_with_output()
        .map_err(|err| boxed_err(format!("wait local-token-mint.sh {label}: {err}")))?;
    if !output.status.success() {
        return Err(boxed_err(format!(
            "E_DISTRIBUTIONX_TOKEN_HELPER_FAILED: local-token-mint.sh {label} exited {:?}: {}",
            output.status.code(),
            String::from_utf8_lossy(&output.stdout)
        )));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    let last_line = stdout
        .lines()
        .rev()
        .find(|line| !line.trim().is_empty())
        .ok_or_else(|| boxed_err("E_DISTRIBUTIONX_TOKEN_HELPER_NO_OUTPUT".to_string()))?;
    Ok(serde_json::from_str(last_line)?)
}

fn resolve_helper_script(env_var: &str, name: &str) -> CliResult<PathBuf> {
    if let Ok(value) = std::env::var(env_var) {
        let path = PathBuf::from(value);
        if !path.exists() {
            return Err(boxed_err(format!(
                "{env_var} points at missing script: {}",
                path.display()
            )));
        }
        return Ok(path);
    }
    if let Ok(repo_root) = std::env::var("DISTRIBUTIONX_REPO_ROOT") {
        let path = PathBuf::from(repo_root).join("scripts").join(name);
        if path.exists() {
            return Ok(path);
        }
    }
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    let path = Path::new(manifest_dir)
        .parent()
        .and_then(|p| p.parent())
        .map(|root| root.join("scripts").join(name))
        .ok_or_else(|| boxed_err(format!("cannot resolve repo root for {name}")))?;
    if !path.exists() {
        return Err(boxed_err(format!(
            "missing helper script: {} (set {env_var} or DISTRIBUTIONX_REPO_ROOT to override)",
            path.display()
        )));
    }
    Ok(path)
}

fn default_wallet_path() -> String {
    if let Ok(path) = std::env::var("NSSA_WALLET_HOME_DIR") {
        return path;
    }
    if let Ok(repo_root) = std::env::var("DISTRIBUTIONX_REPO_ROOT") {
        let path = PathBuf::from(repo_root).join(".scaffold/wallet");
        if path.exists() {
            return path.display().to_string();
        }
    }
    let manifest_dir = env!("CARGO_MANIFEST_DIR");
    if let Some(root) = Path::new(manifest_dir)
        .parent()
        .and_then(|path| path.parent())
    {
        let path = root.join(".scaffold/wallet");
        if path.exists() {
            return path.display().to_string();
        }
    }
    std::env::var("HOME")
        .map(|home| format!("{home}/.nssa/wallet"))
        .unwrap_or_else(|_| ".nssa/wallet".to_string())
}

fn method_id() -> CliResult<()> {
    println!(
        "{}",
        serde_json::json!({
            "status": "METHOD_ID_OK",
            "image_id_hex": image_id_hex()
        })
    );
    Ok(())
}

fn list_airdrops() -> CliResult<()> {
    let registry = load_registry()?;
    println!(
        "{}",
        serde_json::json!({
            "status": "AIRDROPS_OK",
            "state_dir": state_dir().display().to_string(),
            "airdrops": registry.airdrops
        })
    );
    Ok(())
}

fn deterministic_seed(label: &str) -> [u8; 32] {
    let digest = Sha256::digest(label.as_bytes());
    let mut seed = [0u8; 32];
    seed.copy_from_slice(&digest);
    seed
}

fn sample_fixture(out_dir: &Path, claimant_count: usize) -> CliResult<()> {
    if claimant_count == 0 {
        return Err("sample fixture requires at least one claimant".into());
    }
    fs::create_dir_all(out_dir)?;
    let mut csv = String::from("address,raw_amount\n");
    let claimants_dir = out_dir.join("claimants");
    fs::create_dir_all(&claimants_dir)?;

    let csv_path = out_dir.join("eligible.csv");
    let wallet_path = out_dir.join("wallet.seed");
    let admin_seed_path = out_dir.join("admin.seed");
    let keys_path = out_dir.join("fixture-keys.json");
    let claim_destination_commitment_path = out_dir.join("claim_destination_commitment.txt");
    let shielded_destination_path = out_dir.join("shielded_destination.json");

    let mut claimants = Vec::with_capacity(claimant_count);
    for index in 1..=claimant_count {
        let label = format!("distributionx-test-claimant-{index:02}");
        let seed = deterministic_seed(&label);
        let seed_hex = hex::encode(seed);
        let ks = InMemoryKeystore::from_seed(seed)?;
        let public_key_hex = hex::encode(ks.public_ed25519());
        csv.push_str(&format!("{public_key_hex},{DEFAULT_SAMPLE_CLAIM_AMOUNT}\n"));
        let seed_path = claimants_dir.join(format!("claimant-{index:02}.seed"));
        fs::write(&seed_path, &seed_hex)?;
        if index == 1 {
            fs::write(&wallet_path, &seed_hex)?;
        }
        claimants.push(serde_json::json!({
            "index": index,
            "account": format!("Public/{public_key_hex}"),
            "public_key_hex": public_key_hex,
            "seed_hex": seed_hex,
            "seed_path": seed_path.display().to_string()
        }));
    }

    let admin_seed = deterministic_seed("distributionx-test-admin");
    let admin_seed_hex = hex::encode(admin_seed);
    let admin_ks = InMemoryKeystore::from_seed(admin_seed)?;
    let admin_public_key_hex = hex::encode(admin_ks.public_ed25519());
    fs::write(&admin_seed_path, &admin_seed_hex)?;

    let shielded_destination = ShieldedDestinationPacket {
        npk: [42u8; 32],
        vpk: hex::decode("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")?,
        identifier_le: [44u8; 16],
    };
    let destination_commitment = compute_destination_commitment(&shielded_destination);
    fs::write(&csv_path, csv)?;
    fs::write(
        &claim_destination_commitment_path,
        hex::encode(destination_commitment),
    )?;
    write_json(&shielded_destination_path, &shielded_destination)?;
    write_json(
        &keys_path,
        &serde_json::json!({
            "admin": {
                "account": format!("Public/{admin_public_key_hex}"),
                "public_key_hex": admin_public_key_hex,
                "seed_hex": admin_seed_hex,
                "seed_path": admin_seed_path.display().to_string()
            },
            "claimants": claimants
        }),
    )?;
    println!(
        "{}",
        serde_json::json!({
            "status": "SAMPLE_FIXTURE_OK",
            "csv": csv_path.display().to_string(),
            "wallet": wallet_path.display().to_string(),
            "claimant_count": claimant_count,
            "claimants_dir": claimants_dir.display().to_string(),
            "keys": keys_path.display().to_string(),
            "admin_account": format!("Public/{admin_public_key_hex}"),
            "admin_seed": admin_seed_path.display().to_string(),
            "claim_destination_commitment": claim_destination_commitment_path.display().to_string(),
            "shielded_destination": shielded_destination_path.display().to_string()
        })
    );
    Ok(())
}

fn serialized_lez_tx_path() -> PathBuf {
    std::env::var("DISTRIBUTIONX_SERIALIZED_LEZ_TX")
        .map(PathBuf::from)
        .unwrap_or_else(|_| state_dir().join("claim.tx"))
}

fn write_claim_tx(
    prepared: &PreparedClaim,
    proof: Option<&ProofFile>,
    destination_packet: Option<&ShieldedDestinationPacket>,
    path: &Path,
) -> CliResult<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    write_json(
        path,
        &ClaimTxFile::from_prepared(
            prepared,
            proof,
            destination_packet,
            claim_private_opt_in_for_claim_tx(),
        )?,
    )
}

pub fn plain_error(code: &str) -> String {
    code.to_owned()
}

pub fn prove_log_line(value: &str) -> String {
    format!("RISC0_DEV_MODE={value}")
}

pub fn pre_prove_rejection_code(
    state_airdrop_id: &str,
    prepared_airdrop_id: [u8; 32],
    claimed_nullifiers: &BTreeSet<String>,
    prepared_nullifier: [u8; 32],
) -> Option<&'static str> {
    if hex::encode(prepared_airdrop_id) != state_airdrop_id {
        return Some("E_AIRDROP_ID_MISMATCH");
    }
    if claimed_nullifiers.contains(&hex::encode(prepared_nullifier)) {
        return Some("E_ALREADY_CLAIMED");
    }
    None
}

fn state_path() -> PathBuf {
    state_dir().join("state.json")
}

fn registry_path() -> PathBuf {
    state_dir().join("airdrops.json")
}

fn named_state_path(name: &str) -> PathBuf {
    state_dir()
        .join("states")
        .join(format!("{}.json", safe_path_component(name)))
}

fn state_dir() -> PathBuf {
    std::env::var("DISTRIBUTIONX_STATE_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(DEFAULT_STATE_DIR))
}

fn airdrop_name() -> String {
    std::env::var("DISTRIBUTIONX_AIRDROP_NAME")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| DEFAULT_AIRDROP_NAME.to_owned())
}

fn load_state() -> CliResult<LocalAirdropState> {
    Ok(serde_json::from_slice(&fs::read(state_path())?)?)
}

fn load_state_for(airdrop: &str) -> CliResult<LocalAirdropState> {
    if let Ok(state) = load_state() {
        if ensure_airdrop(&state, airdrop).is_ok() {
            return Ok(state);
        }
    }
    let registry = load_registry()?;
    let entry = registry
        .airdrops
        .into_iter()
        .find(|entry| entry.name == airdrop || entry.airdrop_id == airdrop)
        .ok_or_else(|| boxed_err("E_AIRDROP_ID_MISMATCH"))?;
    Ok(serde_json::from_slice(&fs::read(entry.state_path)?)?)
}

fn save_state(state: &LocalAirdropState) -> CliResult<()> {
    fs::create_dir_all(state_dir())?;
    write_json(&state_path(), state)?;
    write_json(&named_state_path(&state.name), state)
}

fn load_registry() -> CliResult<AirdropRegistry> {
    match fs::read(registry_path()) {
        Ok(bytes) => Ok(serde_json::from_slice(&bytes)?),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(AirdropRegistry::default()),
        Err(err) => Err(Box::new(err)),
    }
}

fn upsert_registry(state: &LocalAirdropState) -> CliResult<()> {
    let mut registry = load_registry()?;
    let entry = AirdropRegistryEntry::from_state(state);
    if let Some(existing) = registry
        .airdrops
        .iter_mut()
        .find(|existing| existing.airdrop_id == entry.airdrop_id || existing.name == entry.name)
    {
        *existing = entry;
    } else {
        registry.airdrops.push(entry);
    }
    registry
        .airdrops
        .sort_by_key(|entry| Reverse(entry.updated_at_unix));
    write_json(&registry_path(), &registry)
}

fn ensure_airdrop(state: &LocalAirdropState, airdrop: &str) -> CliResult<()> {
    if airdrop == state.name || airdrop == state.airdrop_id {
        Ok(())
    } else {
        Err(boxed_err("E_AIRDROP_ID_MISMATCH"))
    }
}

fn safe_path_component(value: &str) -> String {
    let mut out = String::new();
    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
            out.push(ch);
        } else {
            out.push('_');
        }
    }
    if out.is_empty() {
        "airdrop".to_owned()
    } else {
        out
    }
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> CliResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, serde_json::to_vec_pretty(value)?)?;
    Ok(())
}

fn read_proof(path: &Path) -> CliResult<ProofFile> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}

fn read_claim_tx(path: &Path) -> CliResult<ClaimTxFile> {
    Ok(serde_json::from_slice(&fs::read(path)?)?)
}

fn read_destination_packet(path: &Path) -> CliResult<ShieldedDestinationPacket> {
    ShieldedDestinationPacket::from_json_slice(&fs::read(path)?)
        .map_err(|err| boxed_err(err.to_string()))
}

fn read_seed(path: &Path) -> CliResult<[u8; 32]> {
    parse_hex_32(fs::read_to_string(path)?.trim())
}

fn parse_id(raw: &str) -> CliResult<[u8; 32]> {
    let normalized = raw
        .strip_prefix("Public/")
        .or_else(|| raw.strip_prefix("Private/"))
        .unwrap_or(raw);
    if normalized.len() == 64 && normalized.bytes().all(|b| b.is_ascii_hexdigit()) {
        return parse_hex_32(normalized);
    }
    if let Ok(bytes) = bs58::decode(normalized).into_vec() {
        if bytes.len() == 32 {
            return bytes
                .try_into()
                .map_err(|_| boxed_err(format!("expected 32-byte account id: {raw}")));
        }
    }
    let mut out = [0u8; 32];
    for (index, byte) in normalized.bytes().enumerate() {
        let slot = index % 32;
        out[slot] = out[slot]
            .wrapping_mul(31)
            .wrapping_add(byte)
            .wrapping_add(index as u8);
    }
    Ok(out)
}

fn parse_hex_32(raw: &str) -> CliResult<[u8; 32]> {
    let bytes = hex::decode(raw)?;
    bytes
        .try_into()
        .map_err(|_| boxed_err(format!("expected 32-byte hex value: {raw}")))
}

fn parse_hex_4(raw: &str) -> CliResult<[u8; 4]> {
    let bytes = hex::decode(raw)?;
    bytes
        .try_into()
        .map_err(|_| boxed_err(format!("expected 4-byte hex value: {raw}")))
}

fn parse_hex_vec(raw: &str) -> CliResult<Vec<u8>> {
    Ok(hex::decode(raw)?)
}

fn image_id_hex() -> String {
    let mut bytes = [0u8; 32];
    for (index, word) in DISTRIBUTIONX_METHODS_GUEST_ID.iter().enumerate() {
        bytes[index * 4..index * 4 + 4].copy_from_slice(&word.to_le_bytes());
    }
    hex::encode(bytes)
}

impl BundleFile {
    fn from_bundle(bundle: &BundleV1) -> Self {
        Self {
            version: bundle.version,
            airdrop_id: hex::encode(bundle.airdrop_id),
            bucket_table_hash: hex::encode(bundle.bucket_table_hash),
            merkle_root: hex::encode(bundle.merkle_root),
            encrypted_rows: bundle
                .encrypted_rows
                .iter()
                .map(EncryptedRowFile::from_row)
                .collect(),
        }
    }

    fn to_bundle(file: BundleFile) -> CliResult<BundleV1> {
        Ok(BundleV1 {
            version: file.version,
            airdrop_id: parse_hex_32(&file.airdrop_id)?,
            bucket_table_hash: parse_hex_32(&file.bucket_table_hash)?,
            merkle_root: parse_hex_32(&file.merkle_root)?,
            encrypted_rows: file
                .encrypted_rows
                .into_iter()
                .map(EncryptedRowFile::to_row)
                .collect::<CliResult<Vec<_>>>()?,
            row_plaintexts_for_test: Vec::new(),
        })
    }
}

impl EncryptedRowFile {
    fn from_row(row: &EncryptedRowV1) -> Self {
        Self {
            version: row.version,
            row_index_le: hex::encode(row.row_index_le),
            ephemeral_x25519_pk: hex::encode(row.ephemeral_x25519_pk),
            leaf: hex::encode(row.leaf),
            ciphertext_plus_tag: hex::encode(row.ciphertext_plus_tag),
        }
    }

    fn to_row(file: EncryptedRowFile) -> CliResult<EncryptedRowV1> {
        Ok(EncryptedRowV1 {
            version: file.version,
            row_index_le: parse_hex_4(&file.row_index_le)?,
            ephemeral_x25519_pk: parse_hex_32(&file.ephemeral_x25519_pk)?,
            leaf: parse_hex_32(&file.leaf)?,
            ciphertext_plus_tag: parse_hex_vec(&file.ciphertext_plus_tag)?
                .try_into()
                .map_err(|_| boxed_err("expected 741-byte ciphertext_plus_tag"))?,
        })
    }
}

impl JournalFile {
    fn from_journal(journal: &ClaimJournal) -> Self {
        Self {
            airdrop_id: hex::encode(journal.airdrop_id),
            merkle_root: hex::encode(journal.merkle_root),
            bucket_id: journal.bucket_id,
            nullifier: hex::encode(journal.nullifier),
            claim_destination_commitment: hex::encode(journal.claim_destination_commitment),
        }
    }

    fn to_journal(&self) -> CliResult<ClaimJournal> {
        Ok(ClaimJournal::new(
            parse_hex_32(&self.airdrop_id)?,
            parse_hex_32(&self.merkle_root)?,
            self.bucket_id,
            parse_hex_32(&self.nullifier)?,
            parse_hex_32(&self.claim_destination_commitment)?,
        ))
    }
}

impl ProofFile {
    fn to_journal(&self) -> CliResult<ClaimJournal> {
        self.journal.to_journal()
    }
}

impl ClaimTxFile {
    fn from_prepared(
        prepared: &PreparedClaim,
        proof: Option<&ProofFile>,
        destination_packet: Option<&ShieldedDestinationPacket>,
        include_private_claim: bool,
    ) -> CliResult<Self> {
        let journal = match proof {
            Some(proof) => proof.to_journal()?,
            None => prepared.proof.journal.clone(),
        };
        // The witness-bearing private_claim block is only emitted when the
        // caller opts into the in-program claim_private verifier. Under the
        // default receipt-based `claim` path the witness stays inside the
        // Risc0 zkVM and never leaves the claimant's machine: claim.tx omits
        // it, so the relayer and any file-system observer only see the
        // receipt and public metadata.
        let include_private_claim = include_private_claim && destination_packet.is_some();
        Ok(Self {
            recipient: format!(
                "Public/{}",
                hex::encode(journal.claim_destination_commitment)
            ),
            recipient_npk: destination_packet.map(|packet| hex::encode(packet.npk)),
            recipient_vpk: destination_packet.map(|packet| hex::encode(&packet.vpk)),
            private_claim: if include_private_claim {
                Some(PrivateClaimTxFile::from_prepared(prepared))
            } else {
                None
            },
            airdrop_id: journal.airdrop_id,
            nullifier: journal.nullifier,
            receipt_bytes: match proof {
                Some(proof) => parse_hex_vec(&proof.receipt_bytes)?,
                None => prepared.proof.receipt_bytes.clone(),
            },
        })
    }
}

fn claim_private_opt_in_for_claim_tx() -> bool {
    matches!(
        std::env::var("DISTRIBUTIONX_USE_CLAIM_PRIVATE")
            .ok()
            .as_deref()
            .map(str::trim),
        Some("1") | Some("true") | Some("yes") | Some("on")
    )
}

impl PrivateClaimTxFile {
    fn from_prepared(prepared: &PreparedClaim) -> Self {
        let journal = &prepared.proof.journal;
        let witness = &prepared.witness;
        Self {
            bucket_id: journal.bucket_id,
            claim_destination_commitment: journal.claim_destination_commitment,
            claimant_address: witness.address,
            salt: witness.salt,
            claim_sig: witness.claim_sig.to_vec(),
            merkle_siblings: witness
                .merkle_path
                .iter()
                .map(|node| node.sibling)
                .collect(),
            merkle_path_is_right: witness
                .merkle_path
                .iter()
                .map(|node| node.is_right)
                .collect(),
        }
    }
}

fn verify_risc0_receipt(proof: &ProofFile) -> CliResult<ClaimJournal> {
    if proof.proof_mode != "risc0-zkvm-receipt" {
        return Err(boxed_err("E_BAD_PROOF_MODE"));
    }
    if proof.risc0_real_proof != "OK" {
        return Err(boxed_err("E_BAD_PROOF_STATUS"));
    }
    let receipt_bytes =
        hex::decode(&proof.receipt_bytes).map_err(|e| boxed_err(format!("E_RECEIPT_HEX:{e}")))?;
    let receipt: Receipt = bincode::deserialize(&receipt_bytes)
        .map_err(|e| boxed_err(format!("E_RECEIPT_DECODE:{e}")))?;
    receipt
        .verify(DISTRIBUTIONX_METHODS_GUEST_ID)
        .map_err(|e| boxed_err(format!("E_RECEIPT_VERIFY:{e}")))?;
    receipt
        .journal
        .decode()
        .map_err(|e| boxed_err(format!("E_RECEIPT_JOURNAL:{e}")))
}

fn submit_claim_to_testnet(
    proof: Option<&ProofFile>,
    relayer: &str,
    tx_path: &Path,
    token_settlement: Option<&TokenSettlementRequest>,
) -> CliResult<String> {
    let command = std::env::var("DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND").ok();
    let serialized_lez_tx = match fs::read(tx_path) {
        Ok(bytes) if !bytes.is_empty() => bytes,
        Ok(_) => return Err(boxed_err("E_EMPTY_SERIALIZED_LEZ_TX")),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
            return Err(boxed_err("E_SERIALIZED_LEZ_TX_NOT_FOUND"));
        }
        Err(err) => return Err(Box::new(err)),
    };
    if serialized_lez_tx.is_empty() {
        return Err(boxed_err("E_EMPTY_SERIALIZED_LEZ_TX"));
    }
    let input = if let Some(proof) = proof {
        let journal = proof.to_journal()?;
        let request = RelayerSubmitRequest::new_with_claimant_built_tx(
            journal,
            parse_hex_vec(&proof.receipt_bytes)?,
            serialized_lez_tx,
            Some(relayer.to_owned()),
        );
        let mut value = serde_json::to_value(&request)?;
        if let Some(settlement) = token_settlement {
            value["token_settlement"] = serde_json::to_value(settlement)?;
        }
        serde_json::to_vec(&value)?
    } else {
        serde_json::to_vec(&serde_json::json!({
            "kind": "distributionx-claim",
            "relayer": relayer,
            "serialized_lez_tx": serialized_lez_tx,
            "token_settlement": token_settlement,
        }))?
    };
    let Some(command) = command else {
        return Err(boxed_err("E_DISTRIBUTIONX_CLAIM_SUBMIT_COMMAND_REQUIRED"));
    };
    let mut child = ProcessCommand::new("bash")
        .arg("-c")
        .arg(command)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;
    child
        .stdin
        .as_mut()
        .ok_or_else(|| boxed_err("E_CLAIM_SUBMIT_STDIN"))?
        .write_all(&input)?;
    let output = child.wait_with_output()?;
    if !output.status.success() {
        return Err(boxed_err("E_CLAIM_SUBMIT_FAILED"));
    }
    let response: RelayerSubmitResponse = serde_json::from_slice(&output.stdout)?;
    if response.tx_id.trim().is_empty() {
        return Err(boxed_err("E_CLAIM_SUBMIT_EMPTY_TX_ID"));
    }
    Ok(response.tx_id)
}

/// Submit a signed transaction request via an operator-supplied bash command.
/// Requires the env var to be set for all RPC types; returns its parsed `tx_id` field.
fn submit_signed_tx(
    op_label: &str,
    env_var: &str,
    required_error_code: &str,
    payload: &serde_json::Value,
    _rpc: &str,
) -> CliResult<String> {
    let input = serde_json::to_vec(payload)?;
    let Some(command) = std::env::var(env_var).ok() else {
        return Err(boxed_err(required_error_code));
    };
    let mut child = ProcessCommand::new("bash")
        .arg("-c")
        .arg(command)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;
    child
        .stdin
        .as_mut()
        .ok_or_else(|| boxed_err(format!("E_{}_SUBMIT_STDIN", op_label.to_uppercase())))?
        .write_all(&input)?;
    let output = child.wait_with_output()?;
    if !output.status.success() {
        return Err(boxed_err(format!(
            "E_{}_SUBMIT_FAILED",
            op_label.to_uppercase()
        )));
    }
    let parsed: serde_json::Value = serde_json::from_slice(&output.stdout)?;
    let tx_id = parsed
        .get("tx_id")
        .and_then(|v| v.as_str())
        .map(|s| s.trim().to_owned())
        .unwrap_or_default();
    if tx_id.is_empty() {
        return Err(boxed_err(format!(
            "E_{}_SUBMIT_EMPTY_TX_ID",
            op_label.to_uppercase()
        )));
    }
    Ok(tx_id)
}

impl LocalAirdropState {
    fn to_airdrop(&self) -> CliResult<Airdrop> {
        let args = InitAirdropArgs {
            distributor: parse_hex_32(&self.distributor)?,
            token_id: parse_hex_32(&self.token_id)?,
            merkle_root: parse_hex_32(&self.merkle_root)?,
            bucket_table_hash: parse_hex_32(&self.bucket_table_hash)?,
            bucket_table: self.bucket_table.clone(),
            vault: parse_id("Public/distributionx-vault")?,
            image_id: distributionx_program::processor::EXPECTED_IMAGE_ID,
            expiry_unix: self.expiry_unix as i64,
            recovery_address: parse_hex_32(&self.recovery_address)?,
            nonce: 1,
        };
        let mut airdrop = distributionx_program::processor::init_airdrop(args, 0)?;
        airdrop.total_funded = self.total_funded;
        airdrop.total_claimed = self.total_claimed;
        airdrop.status = self.status;
        Ok(airdrop)
    }
}

impl AirdropRegistryEntry {
    fn from_state(state: &LocalAirdropState) -> Self {
        Self {
            name: state.name.clone(),
            airdrop_id: state.airdrop_id.clone(),
            distributor: state.distributor.clone(),
            token_id: state.token_id.clone(),
            token_source_account: state.token_source_account.clone(),
            merkle_root: state.merkle_root.clone(),
            bucket_table_hash: state.bucket_table_hash.clone(),
            eligible_count: state.recipient_count,
            total_funded: state.total_funded,
            total_claimed: state.total_claimed,
            expiry_unix: state.expiry_unix,
            recovery_address: state.recovery_address.clone(),
            status: if state.status == 0 {
                "active".to_owned()
            } else {
                "closed".to_owned()
            },
            state_path: named_state_path(&state.name).display().to_string(),
            bundle_path: state.bundle_path.clone(),
            deployment_mode: state.deployment_mode.clone(),
            last_tx_id: state.last_tx_id.clone(),
            updated_at_unix: state.updated_at_unix,
        }
    }
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}

fn boxed_err(message: impl Into<String>) -> Box<dyn std::error::Error> {
    Box::new(std::io::Error::other(message.into()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use distributionx_client::proof::ProofArtifact;
    use distributionx_wallet_ref::MerklePathNode;

    #[test]
    fn claim_tx_file_contains_local_submit_envelope() {
        let journal = ClaimJournal::new([6u8; 32], [7u8; 32], 1, [8u8; 32], [9u8; 32]);
        let prepared = PreparedClaim {
            proof: ProofArtifact {
                journal: journal.clone(),
                receipt_bytes: vec![10u8],
            },
            amount_bucket: 1,
            witness: ClaimWitness {
                address: [1u8; 32],
                salt: [2u8; 32],
                claim_sig: [3u8; 64],
                merkle_path: vec![
                    MerklePathNode {
                        sibling: [4u8; 32],
                        is_right: true,
                    },
                    MerklePathNode {
                        sibling: [5u8; 32],
                        is_right: false,
                    },
                ],
            },
        };
        let proof = ProofFile {
            proof_mode: "risc0-zkvm-receipt".to_owned(),
            risc0_dev_mode: "1".to_owned(),
            risc0_real_proof: "OK".to_owned(),
            airdrop_id: hex::encode(journal.airdrop_id),
            amount_bucket: 1,
            receipt_bytes: "0a".to_owned(),
            journal: JournalFile::from_journal(&journal),
        };

        let tx = ClaimTxFile::from_prepared(&prepared, Some(&proof), None, false)
            .expect("claim tx from proof");
        assert_eq!(tx.recipient, format!("Public/{}", hex::encode([9u8; 32])));
        assert!(tx.recipient_npk.is_none());
        assert!(tx.recipient_vpk.is_none());
        assert!(tx.private_claim.is_none());
        assert_eq!(tx.airdrop_id, [6u8; 32]);
        assert_eq!(tx.nullifier, [8u8; 32]);
        assert_eq!(tx.receipt_bytes, vec![10u8]);

        let encoded = serde_json::to_vec(&tx).expect("claim tx JSON");
        let encoded_json = String::from_utf8(encoded.clone()).expect("claim tx utf8");
        for private_field in [
            "claimant_address",
            "salt",
            "claim_sig",
            "merkle_siblings",
            "merkle_path_is_right",
        ] {
            assert!(
                !encoded_json.contains(private_field),
                "claim tx leaked {private_field}"
            );
        }
        let decoded: ClaimTxFile = serde_json::from_slice(&encoded).expect("claim tx roundtrip");
        assert_eq!(decoded.recipient, tx.recipient);
        assert_eq!(decoded.receipt_bytes, tx.receipt_bytes);
    }

    #[test]
    fn claim_tx_file_carries_private_witness_for_private_destination() {
        let journal = ClaimJournal::new([6u8; 32], [7u8; 32], 1, [8u8; 32], [9u8; 32]);
        let prepared = PreparedClaim {
            proof: ProofArtifact {
                journal: journal.clone(),
                receipt_bytes: vec![10u8],
            },
            amount_bucket: 1,
            witness: ClaimWitness {
                address: [1u8; 32],
                salt: [2u8; 32],
                claim_sig: [3u8; 64],
                merkle_path: vec![MerklePathNode {
                    sibling: [4u8; 32],
                    is_right: true,
                }],
            },
        };
        let proof = ProofFile {
            proof_mode: "risc0-zkvm-receipt".to_owned(),
            risc0_dev_mode: "1".to_owned(),
            risc0_real_proof: "OK".to_owned(),
            airdrop_id: hex::encode(journal.airdrop_id),
            amount_bucket: 1,
            receipt_bytes: "0a".to_owned(),
            journal: JournalFile::from_journal(&journal),
        };
        let destination = ShieldedDestinationPacket {
            npk: [11u8; 32],
            vpk: vec![12u8; 33],
            identifier_le: [13u8; 16],
        };

        let default_tx =
            ClaimTxFile::from_prepared(&prepared, Some(&proof), Some(&destination), false)
                .expect("claim tx default");
        assert_eq!(
            default_tx.recipient_npk.as_deref(),
            Some(hex::encode([11u8; 32]).as_str())
        );
        assert!(default_tx.recipient_vpk.is_some());
        assert!(
            default_tx.private_claim.is_none(),
            "default receipt path must strip the witness from claim.tx",
        );
        let encoded_default =
            String::from_utf8(serde_json::to_vec(&default_tx).expect("default claim tx JSON"))
                .expect("default claim tx utf8");
        for private_field in [
            "claimant_address",
            "salt",
            "claim_sig",
            "merkle_siblings",
            "merkle_path_is_right",
        ] {
            assert!(
                !encoded_default.contains(private_field),
                "default claim tx leaked {private_field}",
            );
        }

        let opt_in_tx =
            ClaimTxFile::from_prepared(&prepared, Some(&proof), Some(&destination), true)
                .expect("claim tx opt-in");
        assert_eq!(
            opt_in_tx.recipient_npk.as_deref(),
            Some(hex::encode([11u8; 32]).as_str())
        );
        assert!(opt_in_tx.recipient_vpk.is_some());
        let private_claim = opt_in_tx
            .private_claim
            .expect("private claim witness under opt-in");
        assert_eq!(private_claim.bucket_id, 1);
        assert_eq!(private_claim.claim_destination_commitment, [9u8; 32]);
        assert_eq!(private_claim.claimant_address, [1u8; 32]);
        assert_eq!(private_claim.salt, [2u8; 32]);
        assert_eq!(private_claim.claim_sig, vec![3u8; 64]);
        assert_eq!(private_claim.merkle_siblings, vec![[4u8; 32]]);
        assert_eq!(private_claim.merkle_path_is_right, vec![true]);
    }
}
