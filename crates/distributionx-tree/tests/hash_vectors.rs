use distributionx_tree::{airdrop_id, bucket_table_hash};
use distributionx_tree::{h_empty, h_leaf, h_node, h_null};
use sha2::{Digest, Sha256};

#[test]
fn hash_schedule_uses_exact_domains() {
    let addr = [1u8; 32];
    let salt = [2u8; 32];
    let mut expected = Sha256::new();
    expected.update(b"logos-distributionx/leaf-v1");
    expected.update(addr);
    expected.update([3u8]);
    expected.update(salt);
    assert_eq!(h_leaf(addr, 3, salt), <[u8; 32]>::from(expected.finalize()));

    let mut empty = Sha256::new();
    empty.update(b"logos-distributionx/empty-v1");
    assert_eq!(h_empty(), <[u8; 32]>::from(empty.finalize()));

    let mut node = Sha256::new();
    node.update(b"logos-distributionx/node-v1");
    node.update([4u8; 32]);
    node.update([5u8; 32]);
    assert_eq!(h_node([4; 32], [5; 32]), <[u8; 32]>::from(node.finalize()));

    let mut null = Sha256::new();
    null.update(b"logos-distributionx/null-v1");
    null.update(salt);
    assert_eq!(h_null(salt), <[u8; 32]>::from(null.finalize()));
}

#[test]
fn bucket_table_hash_changes_when_amount_order_changes() {
    assert_ne!(
        bucket_table_hash(&[100, 500]),
        bucket_table_hash(&[500, 100])
    );
}

#[test]
fn airdrop_id_binds_distribution_parameters() {
    let id1 = airdrop_id([1; 32], [2; 32], [3; 32], [4; 32], 123, [5; 32], 9);
    let id2 = airdrop_id([1; 32], [2; 32], [3; 32], [4; 32], 124, [5; 32], 9);
    assert_ne!(id1, id2);
}
