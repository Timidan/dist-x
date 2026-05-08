use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClaimJournal {
    pub airdrop_id: [u8; 32],
    pub merkle_root: [u8; 32],
    pub bucket_id: u8,
    pub nullifier: [u8; 32],
    pub claim_destination_commitment: [u8; 32],
}

impl ClaimJournal {
    pub fn new(
        airdrop_id: [u8; 32],
        merkle_root: [u8; 32],
        bucket_id: u8,
        nullifier: [u8; 32],
        claim_destination_commitment: [u8; 32],
    ) -> Self {
        Self {
            airdrop_id,
            merkle_root,
            bucket_id,
            nullifier,
            claim_destination_commitment,
        }
    }
}
