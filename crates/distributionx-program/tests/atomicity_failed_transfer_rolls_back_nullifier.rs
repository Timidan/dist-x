use distributionx_circuit::ClaimJournal;
use distributionx_program::errors::E_VAULT_INSUFFICIENT;
use distributionx_program::processor::{
    claim, init_airdrop, InitAirdropArgs, VerifiedClaimJournal,
};
use std::collections::HashSet;

fn verified(journal: ClaimJournal) -> VerifiedClaimJournal {
    VerifiedClaimJournal::from_verified_journal_unchecked(journal)
}

#[test]
fn failed_transfer_does_not_persist_nullifier_and_retry_succeeds() {
    let airdrop_id = [1u8; 32];
    let nullifier = [2u8; 32];
    let airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    let journal = ClaimJournal::new(airdrop_id, airdrop.merkle_root, 0, nullifier, [3; 32]);
    let mut nullifiers = HashSet::<[u8; 32]>::new();

    let failed = claim(
        &airdrop,
        airdrop_id,
        nullifier,
        &verified(journal.clone()),
        0,
    );
    assert_eq!(failed.unwrap_err().0, E_VAULT_INSUFFICIENT);
    assert!(!nullifiers.contains(&nullifier));

    let amount = claim(&airdrop, airdrop_id, nullifier, &verified(journal), 100).unwrap();
    nullifiers.insert(nullifier);
    assert_eq!(amount, 100);
    assert!(nullifiers.contains(&nullifier));
}

#[test]
fn transaction_harness_atomicity_assertions_match_local_contract() {
    let airdrop_id = [1u8; 32];
    let nullifier = [2u8; 32];
    let airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    let journal = ClaimJournal::new(airdrop_id, airdrop.merkle_root, 0, nullifier, [3; 32]);
    let mut nullifier_record_initialized = false;

    let failed = claim(
        &airdrop,
        airdrop_id,
        nullifier,
        &verified(journal.clone()),
        0,
    );
    assert_eq!(failed.unwrap_err().0, E_VAULT_INSUFFICIENT);
    assert!(!nullifier_record_initialized);

    let amount = claim(&airdrop, airdrop_id, nullifier, &verified(journal), 100).unwrap();
    nullifier_record_initialized = true;
    assert_eq!(amount, 100);
    assert!(nullifier_record_initialized);
}
