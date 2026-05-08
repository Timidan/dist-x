pub const E_AIRDROP_CLOSED: u32 = 1;
pub const E_AIRDROP_ID_MISMATCH: u32 = 2;
pub const E_ROOT_MISMATCH: u32 = 3;
pub const E_BUCKET_OUT_OF_RANGE: u32 = 4;
pub const E_BAD_PROOF: u32 = 5;
pub const E_ALREADY_CLAIMED: u32 = 6;
pub const E_VAULT_INSUFFICIENT: u32 = 7;
pub const E_TRANSFER_FAILED: u32 = 8;
pub const E_DISTRIBUTOR_ONLY: u32 = 9;
pub const E_TREE_DEPTH_INVALID: u32 = 10;
pub const E_BUCKET_TABLE_INVALID: u32 = 11;
pub const E_BUCKET_AMOUNT_ZERO: u32 = 12;
pub const E_IMAGE_ID_MISMATCH: u32 = 13;
pub const E_BAD_DESTINATION_COMMITMENT: u32 = 14;
pub const E_OVERFLOW: u32 = 15;
pub const E_EXPIRY_INVALID: u32 = 16;
pub const E_NULLIFIER_MISMATCH: u32 = 17;

#[derive(Debug, Clone, Copy, PartialEq, Eq, thiserror::Error)]
#[error("DistributionX program error {0}")]
pub struct ProgramErrorCode(pub u32);
