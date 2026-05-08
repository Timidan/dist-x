use distributionx_cli::args::{Cli, Command};
use distributionx_cli::commands::{plain_error, pre_prove_rejection_code};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command as ProcessCommand;
use std::time::{SystemTime, UNIX_EPOCH};

#[test]
fn parses_internal_prove_command() {
    let cli = Cli::parse_from([
        "distributionx",
        "prove",
        "--airdrop",
        "aa",
        "--bundle",
        "bundle.bin",
        "--wallet",
        "wallet",
        "--claim-destination-commitment",
        "bb",
    ]);
    assert!(matches!(cli.command, Command::Prove { .. }));
}

#[test]
fn parses_destination_packet_prove_command() {
    let cli = Cli::parse_from([
        "distributionx",
        "prove",
        "--airdrop",
        "aa",
        "--bundle",
        "bundle.bin",
        "--wallet",
        "wallet",
        "--destination-packet",
        "shielded_destination.json",
    ]);
    assert!(matches!(
        cli.command,
        Command::Prove {
            destination_packet: Some(_),
            ..
        }
    ));
}

#[test]
fn parses_check_eligibility_command() {
    let cli = Cli::parse_from([
        "distributionx",
        "check-eligibility",
        "--airdrop",
        "aa",
        "--bundle",
        "bundle.bin",
        "--wallet",
        "wallet",
        "--destination-packet",
        "shielded_destination.json",
    ]);
    assert!(matches!(cli.command, Command::CheckEligibility { .. }));
}

#[test]
fn parses_inspect_destination_command() {
    let cli = Cli::parse_from([
        "distributionx",
        "inspect-destination",
        "--destination-packet",
        "shielded_destination.json",
    ]);
    assert!(matches!(cli.command, Command::InspectDestination { .. }));
}

#[test]
fn parses_create_wallet_command() {
    let cli = Cli::parse_from([
        "distributionx",
        "create-wallet",
        "--out-dir",
        "target/distributionx-testnet",
    ]);
    assert!(matches!(cli.command, Command::CreateWallet { .. }));
}

#[test]
fn parses_token_id_command() {
    let cli = Cli::parse_from(["distributionx", "token-id", "--name", "demo-token"]);
    assert!(matches!(cli.command, Command::TokenId { .. }));
}

#[test]
fn parses_mint_token_command() {
    let cli = Cli::parse_from([
        "distributionx",
        "mint-token",
        "--name",
        "demo-token",
        "--total-supply",
        "42",
        "--offline",
    ]);
    assert!(matches!(
        cli.command,
        Command::MintToken {
            name,
            total_supply: 42,
            offline: true
        } if name == "demo-token"
    ));
}

#[test]
fn parses_sample_fixture_claimant_count() {
    let cli = Cli::parse_from([
        "distributionx",
        "sample-fixture",
        "--out-dir",
        "target/distributionx-testnet",
        "--claimants",
        "30",
    ]);
    assert!(matches!(
        cli.command,
        Command::SampleFixture { claimants: 30, .. }
    ));
}

#[test]
fn cli_help_describes_normal_distribution_flow() {
    let help = cli_stdout(["--help"]);
    assert!(help.contains("Private allowlist distribution CLI for LEZ"));
    assert!(help.contains("create-wallet        Generate a DistributionX claim key seed"));
    assert!(help.contains("token-id             Derive an offline token-id label"));
    assert!(help.contains("mint-token           Register a real LEZ token-program token"));
    assert!(help.contains("claim                Submit a verified proof"));

    let wallet_help = cli_stdout(["create-wallet", "--help"]);
    assert!(wallet_help.contains("Directory to write wallet.seed"));

    let claim_help = cli_stdout(["claim", "--help"]);
    assert!(claim_help.contains("--serialized-lez-tx <PATH>"));
    assert!(claim_help.contains("Serialized LEZ claim transaction"));
}

#[test]
fn token_id_command_prints_localnet_metadata() {
    let output = ProcessCommand::new(env!("CARGO_BIN_EXE_distributionx-cli"))
        .args(["token-id", "--name", "demo-token"])
        .output()
        .expect("run token-id");
    assert!(output.status.success());
    let parsed: serde_json::Value = serde_json::from_slice(&output.stdout).expect("token-id json");
    assert_eq!(parsed["status"], "TOKEN_ID_OK");
    assert_eq!(parsed["name"], "demo-token");
    assert_eq!(parsed["registered"], false);
    assert_eq!(
        parsed["note"],
        "offline-derived label; not registered with the LEZ token program. Run `mint-token` for a real token definition."
    );
    assert!(parsed["token_id"]
        .as_str()
        .expect("token_id string")
        .starts_with("Public/"));
}

#[test]
fn create_wallet_command_writes_seed_when_out_dir_is_set() {
    let out_dir = unique_temp_dir("wallet");
    let output = ProcessCommand::new(env!("CARGO_BIN_EXE_distributionx-cli"))
        .args([
            "create-wallet",
            "--out-dir",
            out_dir.to_str().expect("temp path"),
        ])
        .output()
        .expect("run create-wallet");
    assert!(output.status.success());
    let parsed: serde_json::Value =
        serde_json::from_slice(&output.stdout).expect("create-wallet json");
    assert_eq!(parsed["status"], "CREATE_WALLET_OK");
    assert!(parsed["account"]
        .as_str()
        .expect("account string")
        .starts_with("Public/"));
    let seed_path = parsed["wallet_seed_path"]
        .as_str()
        .expect("wallet_seed_path string");
    let seed = fs::read_to_string(seed_path).expect("wallet seed");
    assert_eq!(seed.len(), 64);
    assert!(seed.bytes().all(|byte| byte.is_ascii_hexdigit()));
    fs::remove_dir_all(out_dir).expect("cleanup wallet temp dir");
}

#[test]
fn sample_fixture_writes_stable_claimant_key_set() {
    let state_dir = unique_temp_dir("sample-keys");
    let fixture = cli_json(["sample-fixture", "--out-dir", path_str(&state_dir)]);
    assert_eq!(fixture["status"], "SAMPLE_FIXTURE_OK");
    assert_eq!(fixture["claimant_count"], 30);

    let csv = fs::read_to_string(state_dir.join("eligible.csv")).expect("eligible csv");
    let lines = csv.lines().collect::<Vec<_>>();
    assert_eq!(lines.len(), 31);
    assert_eq!(lines[0], "address,raw_amount");

    let keys: serde_json::Value =
        serde_json::from_slice(&fs::read(state_dir.join("fixture-keys.json")).expect("keys json"))
            .expect("fixture keys JSON");
    let claimants = keys["claimants"].as_array().expect("claimants array");
    assert_eq!(claimants.len(), 30);
    assert!(keys["admin"]["account"]
        .as_str()
        .expect("admin account")
        .starts_with("Public/"));

    let csv_pubkeys = lines[1..]
        .iter()
        .map(|line| line.split_once(',').expect("csv row").0.to_owned())
        .collect::<BTreeSet<_>>();
    for claimant in claimants {
        let public_key = claimant["public_key_hex"]
            .as_str()
            .expect("claimant public key");
        assert!(csv_pubkeys.contains(public_key));
        let seed_path = claimant["seed_path"].as_str().expect("seed path");
        let seed = fs::read_to_string(seed_path).expect("claimant seed");
        assert_eq!(seed.len(), 64);
        assert!(seed.bytes().all(|byte| byte.is_ascii_hexdigit()));
    }

    let active_seed =
        fs::read_to_string(state_dir.join("wallet.seed")).expect("active wallet seed");
    let claimant_one_seed =
        fs::read_to_string(state_dir.join("claimants/claimant-01.seed")).expect("claimant 1 seed");
    assert_eq!(active_seed, claimant_one_seed);
    assert!(state_dir.join("admin.seed").exists());

    fs::remove_dir_all(state_dir).expect("cleanup sample keys temp dir");
}

#[test]
fn cli_init_and_fund_use_submit_hooks_and_update_registry() {
    let state_dir = unique_temp_dir("init-fund");
    let submit_script = state_dir.join("submit.sh");
    fs::create_dir_all(&state_dir).expect("create state dir");
    fs::write(
        &submit_script,
        r#"#!/usr/bin/env bash
set -euo pipefail
kind="$1"
payload="$(cat)"
case "$payload" in
  \{*) ;;
  *) echo "missing JSON stdin" >&2; exit 9 ;;
esac
printf '{"tx_id":"%s-tx"}\n' "$kind"
"#,
    )
    .expect("write submit script");

    let wallet = cli_json(["create-wallet"]);
    let distributor = wallet["account"].as_str().expect("account");
    let token = cli_json(["token-id", "--name", "cli-flow-token"]);
    let token_id = token["token_id"].as_str().expect("token_id");

    let fixture = cli_json(["sample-fixture", "--out-dir", path_str(&state_dir)]);
    assert_eq!(fixture["status"], "SAMPLE_FIXTURE_OK");

    let submit_command = |kind: &str| format!("bash {} {kind}", shell_quote(&submit_script));
    let init = cli_json_with_env(
        [
            ("DISTRIBUTIONX_STATE_DIR", path_str(&state_dir).to_owned()),
            ("DISTRIBUTIONX_AIRDROP_NAME", "cli-flow-airdrop".to_owned()),
            ("DISTRIBUTIONX_INIT_SUBMIT_COMMAND", submit_command("init")),
        ],
        [
            "init",
            "--csv",
            path_str(&state_dir.join("eligible.csv")),
            "--distributor",
            distributor,
            "--token",
            token_id,
            "--rpc",
            "http://127.0.0.1:3040",
            "--expiry",
            "1893456000",
            "--recovery",
            distributor,
        ],
    );
    assert_eq!(init["status"], "INIT_OK");
    assert_eq!(init["tx_id"], "init-tx");

    let fund = cli_json_with_env(
        [
            ("DISTRIBUTIONX_STATE_DIR", path_str(&state_dir).to_owned()),
            ("DISTRIBUTIONX_FUND_SUBMIT_COMMAND", submit_command("fund")),
        ],
        ["fund", "--airdrop", "cli-flow-airdrop", "--amount", "3000"],
    );
    assert_eq!(fund["status"], "FUND_OK");
    assert_eq!(fund["tx_id"], "fund-tx");
    assert_eq!(fund["total_funded"], 3000);

    let registry = cli_json_with_env(
        [("DISTRIBUTIONX_STATE_DIR", path_str(&state_dir).to_owned())],
        ["list-airdrops"],
    );
    assert_eq!(registry["status"], "AIRDROPS_OK");
    assert_eq!(registry["airdrops"][0]["name"], "cli-flow-airdrop");
    assert_eq!(registry["airdrops"][0]["total_funded"], 3000);

    fs::remove_dir_all(state_dir).expect("cleanup init/fund temp dir");
}

#[test]
fn cli_init_accepts_lez_base58_public_account_ids() {
    let state_dir = unique_temp_dir("base58-init");
    let submit_script = state_dir.join("submit.sh");
    fs::create_dir_all(&state_dir).expect("create state dir");
    fs::write(
        &submit_script,
        r#"#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
printf '{"tx_id":"init-tx"}\n'
"#,
    )
    .expect("write submit script");

    let distributor_bytes = [7u8; 32];
    let recovery_bytes = [8u8; 32];
    let distributor = format!("Public/{}", bs58::encode(distributor_bytes).into_string());
    let recovery = format!("Public/{}", bs58::encode(recovery_bytes).into_string());
    let token = cli_json(["token-id", "--name", "base58-flow-token"]);
    let token_id = token["token_id"].as_str().expect("token_id");

    let fixture = cli_json(["sample-fixture", "--out-dir", path_str(&state_dir)]);
    assert_eq!(fixture["status"], "SAMPLE_FIXTURE_OK");

    let init = cli_json_with_env(
        [
            ("DISTRIBUTIONX_STATE_DIR", path_str(&state_dir).to_owned()),
            (
                "DISTRIBUTIONX_AIRDROP_NAME",
                "base58-flow-airdrop".to_owned(),
            ),
            (
                "DISTRIBUTIONX_INIT_SUBMIT_COMMAND",
                format!("bash {}", shell_quote(&submit_script)),
            ),
        ],
        [
            "init",
            "--csv",
            path_str(&state_dir.join("eligible.csv")),
            "--distributor",
            &distributor,
            "--token",
            token_id,
            "--rpc",
            "http://127.0.0.1:3040",
            "--expiry",
            "1893456000",
            "--recovery",
            &recovery,
        ],
    );
    assert_eq!(init["status"], "INIT_OK");

    let state: serde_json::Value =
        serde_json::from_slice(&fs::read(state_dir.join("state.json")).expect("state json"))
            .expect("state JSON");
    assert_eq!(state["distributor"], hex::encode(distributor_bytes));
    assert_eq!(state["recovery_address"], hex::encode(recovery_bytes));

    fs::remove_dir_all(state_dir).expect("cleanup base58 temp dir");
}

#[test]
fn parses_method_id_command() {
    let cli = Cli::parse_from(["distributionx", "method-id"]);
    assert!(matches!(cli.command, Command::MethodId));
}

#[test]
fn parses_list_airdrops_command() {
    let cli = Cli::parse_from(["distributionx", "list-airdrops"]);
    assert!(matches!(cli.command, Command::ListAirdrops));
}

#[test]
fn cli_errors_keep_machine_codes_for_ci() {
    assert_eq!(plain_error("CLI_DUPLICATE_ADDR"), "CLI_DUPLICATE_ADDR");
}

#[test]
fn prove_command_log_contract_mentions_risc0_dev_mode() {
    assert_eq!(
        distributionx_cli::commands::prove_log_line("0"),
        "RISC0_DEV_MODE=0"
    );
}

#[test]
fn prove_rejects_already_claimed_nullifier_before_risc0() {
    let nullifier = [9u8; 32];
    let mut claimed = BTreeSet::new();
    claimed.insert(hex::encode(nullifier));

    assert_eq!(
        pre_prove_rejection_code(&hex::encode([1u8; 32]), [1u8; 32], &claimed, nullifier),
        Some("E_ALREADY_CLAIMED")
    );
}

#[test]
fn prove_rejects_wrong_distribution_before_risc0() {
    assert_eq!(
        pre_prove_rejection_code(
            &hex::encode([1u8; 32]),
            [2u8; 32],
            &BTreeSet::new(),
            [9u8; 32]
        ),
        Some("E_AIRDROP_ID_MISMATCH")
    );
}

fn unique_temp_dir(label: &str) -> PathBuf {
    std::env::temp_dir().join(format!(
        "distributionx-cli-{label}-test-{}-{}",
        std::process::id(),
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time")
            .as_nanos()
    ))
}

fn path_str(path: &Path) -> &str {
    path.to_str().expect("utf-8 temp path")
}

fn shell_quote(path: &Path) -> String {
    format!("'{}'", path_str(path).replace('\'', "'\\''"))
}

fn cli_stdout<const N: usize>(args: [&str; N]) -> String {
    let output = ProcessCommand::new(env!("CARGO_BIN_EXE_distributionx-cli"))
        .args(args)
        .output()
        .expect("run distributionx-cli");
    assert!(
        output.status.success(),
        "distributionx-cli failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).expect("utf-8 cli stdout")
}

fn cli_json<const N: usize>(args: [&str; N]) -> serde_json::Value {
    cli_json_with_env([], args)
}

fn cli_json_with_env<const E: usize, const N: usize>(
    envs: [(&str, String); E],
    args: [&str; N],
) -> serde_json::Value {
    let mut command = ProcessCommand::new(env!("CARGO_BIN_EXE_distributionx-cli"));
    command.args(args);
    for (key, value) in envs {
        command.env(key, value);
    }
    let output = command.output().expect("run distributionx-cli");
    assert!(
        output.status.success(),
        "distributionx-cli failed\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    serde_json::from_slice(&output.stdout).expect("cli json")
}
