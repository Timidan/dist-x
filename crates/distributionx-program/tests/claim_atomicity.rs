use distributionx_circuit::ClaimJournal;
use distributionx_program::errors::{E_TRANSFER_FAILED, E_VAULT_INSUFFICIENT};
use distributionx_program::processor::{
    claim, init_airdrop, InitAirdropArgs, VerifiedClaimJournal,
};
use std::collections::HashSet;

fn verified(journal: ClaimJournal) -> VerifiedClaimJournal {
    VerifiedClaimJournal::from_verified_journal_unchecked(journal)
}

fn claim_with_injected_transfer(
    nullifiers: &mut HashSet<[u8; 32]>,
    transfer: impl FnOnce(u64) -> Result<(), u32>,
) -> Result<u64, u32> {
    let airdrop_id = [1u8; 32];
    let nullifier = [2u8; 32];
    let mut airdrop_args = InitAirdropArgs::valid_for_test();
    airdrop_args.merkle_root = [3u8; 32];
    let mut airdrop = init_airdrop(airdrop_args, 100).map_err(|err| err.0)?;
    airdrop.total_funded = 100;
    let journal = ClaimJournal::new(airdrop_id, airdrop.merkle_root, 0, nullifier, [4; 32]);

    let amount =
        claim(&airdrop, airdrop_id, nullifier, &verified(journal), 100).map_err(|err| err.0)?;
    transfer(amount)?;
    nullifiers.insert(nullifier);
    Ok(amount)
}

#[test]
fn failed_transfer_does_not_persist_nullifier_pda() {
    let mut nullifiers = HashSet::<[u8; 32]>::new();

    let failed = claim_with_injected_transfer(&mut nullifiers, |_| Err(E_TRANSFER_FAILED));

    assert_eq!(failed.unwrap_err(), E_TRANSFER_FAILED);
    assert!(!nullifiers.contains(&[2u8; 32]));
}

#[test]
fn validation_failure_does_not_persist_nullifier_pda() {
    let airdrop_id = [1u8; 32];
    let nullifier = [2u8; 32];
    let airdrop = init_airdrop(InitAirdropArgs::valid_for_test(), 100).unwrap();
    let journal = ClaimJournal::new(airdrop_id, airdrop.merkle_root, 0, nullifier, [4; 32]);
    let nullifiers = HashSet::<[u8; 32]>::new();

    let failed = claim(&airdrop, airdrop_id, nullifier, &verified(journal), 0);

    assert_eq!(failed.unwrap_err().0, E_VAULT_INSUFFICIENT);
    assert!(!nullifiers.contains(&nullifier));
}
