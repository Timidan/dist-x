use crate::csv::CsvRow;
use crate::errors::DistributionXTreeError;
use crate::hash::h_leaf;
use crate::merkle::MerkleTree;
use chacha20poly1305::aead::{AeadInPlace, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use distributionx_wallet_ref::{
    derive_aead_key_nonce, BundleContext, EncryptedRowV1, RowPlaintext,
};
use rand_core::{OsRng, RngCore};
use x25519_dalek::{PublicKey, StaticSecret};

#[derive(Clone, Debug)]
pub struct BundleV1 {
    pub version: u8,
    pub airdrop_id: [u8; 32],
    pub bucket_table_hash: [u8; 32],
    pub merkle_root: [u8; 32],
    pub encrypted_rows: Vec<EncryptedRowV1>,
    pub row_plaintexts_for_test: Vec<RowPlaintext>,
}

pub fn build_bundle(
    airdrop_id: [u8; 32],
    bucket_table_hash: [u8; 32],
    merkle_root_hint: [u8; 32],
    rows: &[CsvRow],
) -> Result<BundleV1, DistributionXTreeError> {
    build_bundle_with_airdrop_id(bucket_table_hash, merkle_root_hint, rows, |_| airdrop_id)
}

pub fn build_bundle_with_airdrop_id<F>(
    bucket_table_hash: [u8; 32],
    merkle_root_hint: [u8; 32],
    rows: &[CsvRow],
    airdrop_id_for_root: F,
) -> Result<BundleV1, DistributionXTreeError>
where
    F: FnOnce([u8; 32]) -> [u8; 32],
{
    let mut salts = Vec::with_capacity(rows.len());
    let mut leaves = Vec::with_capacity(rows.len());
    for row in rows {
        let mut salt = [0u8; 32];
        OsRng.fill_bytes(&mut salt);
        if salts.contains(&salt) {
            return Err(DistributionXTreeError::CliSaltDuplicate);
        }
        salts.push(salt);
        leaves.push(h_leaf(row.address, row.bucket_id, salt));
    }

    let tree = MerkleTree::from_leaves(leaves.clone());
    let merkle_root = if merkle_root_hint == [0; 32] {
        tree.root()
    } else {
        merkle_root_hint
    };
    let airdrop_id = airdrop_id_for_root(merkle_root);
    let ctx = BundleContext {
        airdrop_id,
        merkle_root,
        bucket_table_hash,
    };

    let mut encrypted_rows = Vec::with_capacity(rows.len());
    let mut row_plaintexts_for_test = Vec::with_capacity(rows.len());
    for (index, row) in rows.iter().enumerate() {
        let recipient_pk = distributionx_wallet_ref::ed25519_public_to_x25519(row.address)
            .map_err(|_| DistributionXTreeError::CliAddrNonCanonical)?;
        let ephemeral = StaticSecret::random_from_rng(OsRng);
        let ephemeral_pk = PublicKey::from(&ephemeral).to_bytes();
        let leaf = leaves[index];
        let path = tree.path(index).unwrap();
        let mut fixed_path = [distributionx_wallet_ref::MerklePathNode::default(); 20];
        fixed_path.copy_from_slice(&path.nodes);
        let plain = RowPlaintext {
            address: row.address,
            bucket_id: row.bucket_id,
            salt: salts[index],
            merkle_path: fixed_path,
        };
        let mut encoded = encode_plaintext(&plain).to_vec();
        let mut encrypted = EncryptedRowV1 {
            version: 1,
            row_index_le: (index as u32).to_le_bytes(),
            ephemeral_x25519_pk: ephemeral_pk,
            leaf,
            ciphertext_plus_tag: [0; 741],
        };
        let shared = ephemeral
            .diffie_hellman(&PublicKey::from(recipient_pk))
            .to_bytes();
        let (key, nonce) = derive_aead_key_nonce(ctx, &encrypted, recipient_pk, shared);
        let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
        let tag = cipher
            .encrypt_in_place_detached(
                Nonce::from_slice(&nonce),
                &distributionx_wallet_ref::bundle_aad(ctx, &encrypted, recipient_pk),
                &mut encoded,
            )
            .map_err(|_| DistributionXTreeError::CliSaltCsprngFail)?;
        encrypted.ciphertext_plus_tag[..725].copy_from_slice(&encoded);
        encrypted.ciphertext_plus_tag[725..741].copy_from_slice(&tag);
        encrypted_rows.push(encrypted);
        row_plaintexts_for_test.push(plain);
    }

    Ok(BundleV1 {
        version: 1,
        airdrop_id,
        bucket_table_hash,
        merkle_root,
        encrypted_rows,
        row_plaintexts_for_test,
    })
}

fn encode_plaintext(row: &RowPlaintext) -> [u8; RowPlaintext::LEN] {
    let mut out = [0u8; RowPlaintext::LEN];
    out[0..32].copy_from_slice(&row.address);
    out[32] = row.bucket_id;
    out[33..65].copy_from_slice(&row.salt);
    let mut offset = 65;
    for node in &row.merkle_path {
        out[offset..offset + 32].copy_from_slice(&node.sibling);
        out[offset + 32] = u8::from(node.is_right);
        offset += 33;
    }
    out
}
