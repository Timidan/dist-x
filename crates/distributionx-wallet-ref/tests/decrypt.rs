mod fixtures;

use distributionx_wallet_ref::{
    decrypt_row_with_x25519_secret, trial_decrypt_bundle, BundleContext, DistributionXWalletError,
    EncryptedRowV1, MerklePathNode, RowPlaintext,
};
use fixtures::{ctx, plaintext, sealed_row};

#[test]
fn encrypted_row_and_plaintext_have_fixed_lengths() {
    assert_eq!(EncryptedRowV1::LEN, 810);
    assert_eq!(RowPlaintext::LEN, 725);
    assert_eq!(MerklePathNode::LEN, 33);
    assert_eq!(BundleContext::HKDF_INFO_LEN, 165);
    assert_eq!(BundleContext::AAD_LEN, 232);
}

#[test]
fn secret_plaintext_debug_is_redacted() {
    let row = RowPlaintext {
        address: [1; 32],
        bucket_id: 7,
        salt: [2; 32],
        merkle_path: [MerklePathNode {
            sibling: [3; 32],
            is_right: false,
        }; 20],
    };
    assert_eq!(format!("{row:?}"), "RowPlaintext(<redacted>)");
}

#[test]
fn hkdf_info_and_aad_match_exact_spec_lengths() {
    let ctx = BundleContext {
        airdrop_id: [1; 32],
        merkle_root: [2; 32],
        bucket_table_hash: [3; 32],
    };
    let row = EncryptedRowV1 {
        version: 1,
        row_index_le: 4u32.to_le_bytes(),
        ephemeral_x25519_pk: [5; 32],
        leaf: [6; 32],
        ciphertext_plus_tag: [0; 741],
    };
    let recipient = [7u8; 32];
    assert_eq!(
        distributionx_wallet_ref::bundle_hkdf_info(ctx, &row, recipient).len(),
        165
    );
    assert_eq!(
        distributionx_wallet_ref::bundle_aad(ctx, &row, recipient).len(),
        232
    );
}

#[test]
fn decrypts_the_one_authenticated_row() {
    let sk = [55u8; 32];
    let row = sealed_row(sk);
    assert_eq!(
        decrypt_row_with_x25519_secret(ctx(), row, sk).unwrap(),
        plaintext()
    );
}

#[test]
fn tag_failure_returns_none_equivalent_error() {
    let sk = [55u8; 32];
    let mut row = sealed_row(sk);
    row.ciphertext_plus_tag[0] ^= 1;
    assert_eq!(
        decrypt_row_with_x25519_secret(ctx(), row, sk).unwrap_err(),
        DistributionXWalletError::NoDecryptableRow
    );
}

#[test]
fn wrong_recipient_cannot_decrypt() {
    let row = sealed_row([55u8; 32]);
    assert_eq!(
        decrypt_row_with_x25519_secret(ctx(), row, [56u8; 32]).unwrap_err(),
        DistributionXWalletError::NoDecryptableRow
    );
}

#[test]
fn trial_decrypt_requires_exactly_one_row() {
    let sk = [55u8; 32];
    let good = sealed_row(sk);
    let mut bad = sealed_row(sk);
    bad.ciphertext_plus_tag[0] ^= 1;
    assert_eq!(
        trial_decrypt_bundle(ctx(), vec![bad, good], sk).unwrap(),
        plaintext()
    );
}
