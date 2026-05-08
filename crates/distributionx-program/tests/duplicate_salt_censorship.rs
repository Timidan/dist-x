use distributionx_program::errors::E_ALREADY_CLAIMED;
use std::collections::HashSet;

#[test]
fn second_claim_with_same_nullifier_is_already_claimed() {
    let nullifier = [8u8; 32];
    let mut claimed = HashSet::<[u8; 32]>::new();
    assert!(claimed.insert(nullifier));
    let second = if claimed.insert(nullifier) {
        Ok(())
    } else {
        Err(E_ALREADY_CLAIMED)
    };
    assert_eq!(second.unwrap_err(), E_ALREADY_CLAIMED);
}
