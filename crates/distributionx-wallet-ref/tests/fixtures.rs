use chacha20poly1305::aead::{AeadInPlace, KeyInit};
use chacha20poly1305::{ChaCha20Poly1305, Key, Nonce};
use distributionx_wallet_ref::{BundleContext, EncryptedRowV1, MerklePathNode, RowPlaintext};
use x25519_dalek::{PublicKey, StaticSecret};

pub fn ctx() -> BundleContext {
    BundleContext {
        airdrop_id: [10; 32],
        merkle_root: [11; 32],
        bucket_table_hash: [12; 32],
    }
}

pub fn plaintext() -> RowPlaintext {
    RowPlaintext {
        address: [1; 32],
        bucket_id: 3,
        salt: [2; 32],
        merkle_path: [MerklePathNode {
            sibling: [4; 32],
            is_right: true,
        }; 20],
    }
}

pub fn encode_plaintext(row: &RowPlaintext) -> [u8; RowPlaintext::LEN] {
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

pub fn sealed_row(recipient_sk: [u8; 32]) -> EncryptedRowV1 {
    let ctx = ctx();
    let recipient_secret = StaticSecret::from(recipient_sk);
    let recipient_pk = PublicKey::from(&recipient_secret).to_bytes();
    let ephemeral_secret = StaticSecret::from([77u8; 32]);
    let ephemeral_pk = PublicKey::from(&ephemeral_secret).to_bytes();
    let mut row = EncryptedRowV1 {
        version: 1,
        row_index_le: 0u32.to_le_bytes(),
        ephemeral_x25519_pk: ephemeral_pk,
        leaf: [13; 32],
        ciphertext_plus_tag: [0; 741],
    };
    let shared = ephemeral_secret
        .diffie_hellman(&PublicKey::from(recipient_pk))
        .to_bytes();
    let (key, nonce) =
        distributionx_wallet_ref::derive_aead_key_nonce(ctx, &row, recipient_pk, shared);
    let cipher = ChaCha20Poly1305::new(Key::from_slice(&key));
    let mut body = encode_plaintext(&plaintext()).to_vec();
    let tag = cipher
        .encrypt_in_place_detached(
            Nonce::from_slice(&nonce),
            &distributionx_wallet_ref::bundle_aad(ctx, &row, recipient_pk),
            &mut body,
        )
        .unwrap();
    row.ciphertext_plus_tag[..725].copy_from_slice(&body);
    row.ciphertext_plus_tag[725..741].copy_from_slice(&tag);
    row
}
