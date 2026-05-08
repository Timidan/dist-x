use sha2::{Digest, Sha256};

pub fn bucket_table_hash(bucket_table: &[u64]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/bucket-table-v1");
    h.update((bucket_table.len() as u32).to_le_bytes());
    for amount in bucket_table {
        h.update(amount.to_le_bytes());
    }
    h.finalize().into()
}

pub fn airdrop_id(
    distributor_addr: [u8; 32],
    token_id: [u8; 32],
    merkle_root: [u8; 32],
    bucket_table_hash: [u8; 32],
    expiry_unix: u64,
    recovery_address: [u8; 32],
    nonce: u64,
) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/airdrop-id-v1");
    h.update(distributor_addr);
    h.update(token_id);
    h.update(merkle_root);
    h.update([20u8]);
    h.update(bucket_table_hash);
    h.update(expiry_unix.to_le_bytes());
    h.update(recovery_address);
    h.update(nonce.to_le_bytes());
    h.finalize().into()
}
