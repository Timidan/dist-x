use crate::types::{
    BundleContext, DistributionXWalletError, EncryptedRowV1, MerklePathNode, RowPlaintext,
};
use chacha20poly1305::aead::{AeadInPlace, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce, Tag};
use hkdf::Hkdf;
use sha2::{Digest, Sha256};
use x25519_dalek::{PublicKey, StaticSecret};

pub fn hkdf_salt(ctx: BundleContext) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"logos-distributionx/bundle-hkdf-salt-v1");
    h.update(ctx.airdrop_id);
    h.update(ctx.merkle_root);
    h.finalize().into()
}

pub fn hkdf_info(
    ctx: BundleContext,
    row: &EncryptedRowV1,
    recipient_x25519_pk: [u8; 32],
) -> Vec<u8> {
    let mut info = Vec::with_capacity(BundleContext::HKDF_INFO_LEN);
    info.extend_from_slice(b"logos-distributionx/bundle-row-v1");
    info.extend_from_slice(&ctx.airdrop_id);
    info.extend_from_slice(&row.row_index_le);
    info.extend_from_slice(&row.ephemeral_x25519_pk);
    info.extend_from_slice(&recipient_x25519_pk);
    info.extend_from_slice(&row.leaf);
    info
}

pub fn aad(ctx: BundleContext, row: &EncryptedRowV1, recipient_x25519_pk: [u8; 32]) -> Vec<u8> {
    let mut ad = Vec::with_capacity(BundleContext::AAD_LEN);
    ad.extend_from_slice(b"logos-distributionx/bundle-row-ad-v1");
    ad.extend_from_slice(&ctx.airdrop_id);
    ad.extend_from_slice(&ctx.merkle_root);
    ad.extend_from_slice(&row.row_index_le);
    ad.extend_from_slice(&ctx.bucket_table_hash);
    ad.extend_from_slice(&row.ephemeral_x25519_pk);
    ad.extend_from_slice(&recipient_x25519_pk);
    ad.extend_from_slice(&row.leaf);
    ad
}

pub fn derive_aead_key_nonce(
    ctx: BundleContext,
    row: &EncryptedRowV1,
    recipient_x25519_pk: [u8; 32],
    shared_secret: [u8; 32],
) -> ([u8; 32], [u8; 12]) {
    let hk = Hkdf::<Sha256>::new(Some(&hkdf_salt(ctx)), &shared_secret);
    let mut okm = [0u8; 44];
    hk.expand(&hkdf_info(ctx, row, recipient_x25519_pk), &mut okm)
        .expect("44-byte HKDF output is valid");
    let mut key = [0u8; 32];
    let mut nonce = [0u8; 12];
    key.copy_from_slice(&okm[..32]);
    nonce.copy_from_slice(&okm[32..44]);
    (key, nonce)
}

pub fn parse_plaintext(bytes: &[u8; RowPlaintext::LEN]) -> RowPlaintext {
    let mut address = [0u8; 32];
    address.copy_from_slice(&bytes[0..32]);
    let bucket_id = bytes[32];
    let mut salt = [0u8; 32];
    salt.copy_from_slice(&bytes[33..65]);
    let mut merkle_path = [MerklePathNode::default(); 20];
    let mut offset = 65;
    for node in &mut merkle_path {
        node.sibling.copy_from_slice(&bytes[offset..offset + 32]);
        node.is_right = bytes[offset + 32] == 1;
        offset += 33;
    }
    RowPlaintext {
        address,
        bucket_id,
        salt,
        merkle_path,
    }
}

pub fn decrypt_row_with_x25519_secret(
    ctx: BundleContext,
    row: EncryptedRowV1,
    recipient_x25519_sk: [u8; 32],
) -> Result<RowPlaintext, DistributionXWalletError> {
    if row.version != 1 {
        return Err(DistributionXWalletError::InvalidRowVersion);
    }
    let secret = StaticSecret::from(recipient_x25519_sk);
    let recipient_pk = PublicKey::from(&secret).to_bytes();
    let shared = secret
        .diffie_hellman(&PublicKey::from(row.ephemeral_x25519_pk))
        .to_bytes();
    let (key, nonce) = derive_aead_key_nonce(ctx, &row, recipient_pk, shared);
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    let mut plaintext = row.ciphertext_plus_tag[..725].to_vec();
    let tag = Tag::from_slice(&row.ciphertext_plus_tag[725..741]);
    cipher
        .decrypt_in_place_detached(
            Nonce::from_slice(&nonce),
            &aad(ctx, &row, recipient_pk),
            &mut plaintext,
            tag,
        )
        .map_err(|_| DistributionXWalletError::NoDecryptableRow)?;
    let boxed: [u8; RowPlaintext::LEN] = plaintext
        .try_into()
        .map_err(|_| DistributionXWalletError::InvalidPlaintextLength)?;
    Ok(parse_plaintext(&boxed))
}

pub fn trial_decrypt_bundle<I>(
    ctx: BundleContext,
    rows: I,
    recipient_x25519_sk: [u8; 32],
) -> Result<RowPlaintext, DistributionXWalletError>
where
    I: IntoIterator<Item = EncryptedRowV1>,
{
    let mut found = None;
    for row in rows {
        if let Ok(plain) = decrypt_row_with_x25519_secret(ctx, row, recipient_x25519_sk) {
            if found.is_some() {
                return Err(DistributionXWalletError::MultipleDecryptableRows);
            }
            found = Some(plain);
        }
    }
    found.ok_or(DistributionXWalletError::NoDecryptableRow)
}
