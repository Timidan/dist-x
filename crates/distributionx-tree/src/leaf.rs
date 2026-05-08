use crate::hash::h_leaf;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct LeafInput {
    pub address: [u8; 32],
    pub bucket_id: u8,
    pub salt: [u8; 32],
}

pub fn leaf_hash(input: LeafInput) -> [u8; 32] {
    h_leaf(input.address, input.bucket_id, input.salt)
}
