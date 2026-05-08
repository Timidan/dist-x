use distributionx_wallet_ref::{MerklePathNode, RowPlaintext};
use zeroize::Zeroize;

#[test]
fn row_plaintext_zeroizes_salt_address_and_path() {
    let mut row = RowPlaintext {
        address: [1; 32],
        bucket_id: 2,
        salt: [3; 32],
        merkle_path: [MerklePathNode {
            sibling: [4; 32],
            is_right: true,
        }; 20],
    };
    row.zeroize();
    assert_eq!(row.address, [0; 32]);
    assert_eq!(row.bucket_id, 0);
    assert_eq!(row.salt, [0; 32]);
    assert!(row
        .merkle_path
        .iter()
        .all(|n| n.sibling == [0; 32] && !n.is_right));
}
