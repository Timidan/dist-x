use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Airdrop {
    pub distributor: [u8; 32],
    pub token_id: [u8; 32],
    pub merkle_root: [u8; 32],
    pub tree_depth: u8,
    pub bucket_table_hash: [u8; 32],
    pub bucket_table: Vec<u64>,
    pub vault: [u8; 32],
    pub image_id: [u8; 32],
    pub expiry_unix: i64,
    pub recovery_address: [u8; 32],
    pub total_funded: u64,
    pub total_claimed: u64,
    pub created_at: i64,
    pub status: u8,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct NullifierRecord {
    pub claimed_at: i64,
}
