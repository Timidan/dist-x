use distributionx_circuit::ClaimJournal;
use distributionx_program::errors::*;
use distributionx_program::idl::emit_idl_json;
use distributionx_program::processor::{
    claim, claim_ppe, close, fund, init_airdrop, InitAirdropArgs, VerifiedClaimJournal,
};

fn verified(journal: ClaimJournal) -> VerifiedClaimJournal {
    VerifiedClaimJournal::from_verified_journal_unchecked(journal)
}

#[test]
fn error_codes_are_stable() {
    assert_eq!(E_AIRDROP_CLOSED, 1);
    assert_eq!(E_ALREADY_CLAIMED, 6);
    assert_eq!(E_NULLIFIER_MISMATCH, 17);
}

#[test]
fn init_rejects_invalid_bucket_table_and_expiry() {
    let mut args = InitAirdropArgs::valid_for_test();
    args.bucket_table.clear();
    assert_eq!(
        init_airdrop(args.clone(), 100).unwrap_err().0,
        E_BUCKET_TABLE_INVALID
    );

    let mut args = InitAirdropArgs::valid_for_test();
    args.bucket_table = vec![0];
    assert_eq!(
        init_airdrop(args.clone(), 100).unwrap_err().0,
        E_BUCKET_AMOUNT_ZERO
    );

    let mut args = InitAirdropArgs::valid_for_test();
    args.expiry_unix = 99;
    assert_eq!(init_airdrop(args, 100).unwrap_err().0, E_EXPIRY_INVALID);
}

#[test]
fn fund_rejects_total_funded_overflow() {
    let mut airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    airdrop.total_funded = u64::MAX;
    assert_eq!(fund(&mut airdrop, 1).unwrap_err().0, E_OVERFLOW);
}

#[test]
fn claim_rejects_journal_mismatches_and_closed_airdrop() {
    let airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    let mut journal = ClaimJournal::new([7; 32], airdrop.merkle_root, 0, [8; 32], [9; 32]);
    assert_eq!(
        claim(&airdrop, [1; 32], [8; 32], &verified(journal.clone()), 100)
            .unwrap_err()
            .0,
        E_AIRDROP_ID_MISMATCH
    );

    journal.airdrop_id = [1; 32];
    journal.merkle_root = [0; 32];
    assert_eq!(
        claim(&airdrop, [1; 32], [8; 32], &verified(journal), 100)
            .unwrap_err()
            .0,
        E_ROOT_MISMATCH
    );
}

#[test]
fn claim_ppe_validates_inline_witness_settlement_without_receipt() {
    let mut airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    airdrop.total_funded = 100;

    let amount = claim_ppe(&airdrop, [1; 32], 0, [8; 32], [9; 32], 100)
        .expect("PPE claim settlement should not require a Risc0 receipt");
    assert_eq!(amount, 100);

    assert_eq!(
        claim_ppe(&airdrop, [1; 32], 0, [8; 32], [0; 32], 100)
            .unwrap_err()
            .0,
        E_BAD_DESTINATION_COMMITMENT
    );
    assert_eq!(
        claim_ppe(&airdrop, [1; 32], 9, [8; 32], [9; 32], 100)
            .unwrap_err()
            .0,
        E_BUCKET_OUT_OF_RANGE
    );
}

#[test]
fn close_is_distributor_only_and_allowed_before_expiry() {
    let mut airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    assert_eq!(
        close(&mut airdrop, [9; 32]).unwrap_err().0,
        E_DISTRIBUTOR_ONLY
    );
    close(&mut airdrop, [1; 32]).unwrap();
    assert_eq!(airdrop.status, 1);
}

#[test]
fn idl_contains_all_instructions_and_error_codes() {
    let idl = emit_idl_json();
    assert!(idl.contains("\"init_airdrop\""));
    assert!(idl.contains("\"fund\""));
    assert!(idl.contains("\"claim\""));
    assert!(idl.contains("\"claim_private\""));
    assert!(idl.contains("\"claim_ppe\""));
    assert!(idl.contains("\"close\""));
    assert!(idl.contains("\"E_BAD_PROOF\""));
    assert!(idl.contains("\"E_ALREADY_CLAIMED\""));
}
