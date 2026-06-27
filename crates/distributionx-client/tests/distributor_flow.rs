use distributionx_client::attest::SelfDisclosure;
use distributionx_client::{build_distribution, DistributionDraft, DistributionXClientError};
use distributionx_tree::airdrop_id;
use distributionx_wallet_ref::{DistributionXKeystore, InMemoryKeystore};

#[test]
fn distribution_draft_requires_non_empty_name() {
    assert_eq!(
        DistributionDraft::new("", [1; 32]).unwrap_err(),
        DistributionXClientError::InvalidDraftName
    );
}

#[test]
fn build_distribution_parses_csv_and_creates_bundle() {
    let mut csv = String::from("address,raw_amount\n");
    for i in 0..8u8 {
        let ks = InMemoryKeystore::from_seed([i + 1; 32]).unwrap();
        let address = ks.public_ed25519();
        csv.push_str(
            &address
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>(),
        );
        csv.push_str(",100\n");
    }
    let draft = DistributionDraft::new("real drop", [7; 32]).unwrap();
    let built = build_distribution(draft, &csv, [1; 32], [2; 32], 999, [3; 32], 4).unwrap();
    assert_eq!(built.bundle.encrypted_rows.len(), 8);
    assert_eq!(built.bucket_table, vec![100]);
}

#[test]
fn build_distribution_binds_airdrop_id_to_computed_merkle_root() {
    let mut csv = String::from("address,raw_amount\n");
    for i in 0..8u8 {
        let ks = InMemoryKeystore::from_seed([i + 1; 32]).unwrap();
        let address = ks.public_ed25519();
        csv.push_str(
            &address
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<String>(),
        );
        csv.push_str(",100\n");
    }
    let distributor = [7; 32];
    let token_id = [1; 32];
    let recovery_address = [3; 32];
    let draft = DistributionDraft::new("real drop", distributor).unwrap();
    let built =
        build_distribution(draft, &csv, token_id, [0; 32], 999, recovery_address, 4).unwrap();
    assert_eq!(
        built.airdrop_id,
        airdrop_id(
            distributor,
            token_id,
            built.bundle.merkle_root,
            built.bundle.bucket_table_hash,
            999,
            recovery_address,
            4,
        )
    );
}

#[test]
fn disclosure_json_names_reputational_fields() {
    let disclosure = SelfDisclosure::for_test();
    let json = serde_json::to_string(&disclosure).unwrap();
    assert!(json.contains("population_per_bucket"));
    assert!(json.contains("salt_csprng_seed_hash"));
    assert!(json.contains("\"attestation_version\":\"v1\""));
}

#[test]
fn module_author_bindings_expose_program_instructions() {
    assert_eq!(
        distributionx_bindings::instruction_names(),
        vec![
            "init_airdrop",
            "fund",
            "claim",
            "claim_private",
            "claim_ppe",
            "close"
        ]
    );
}
