use distributionx_tree::{build_bundle, h_empty, h_leaf, h_null, CsvRow, LeafInput, MerkleTree};
use distributionx_wallet_ref::{BundleContext, DistributionXKeystore, InMemoryKeystore};

#[test]
fn depth_20_tree_verifies_path_for_populated_leaf() {
    let leaf = h_leaf([1; 32], 0, [2; 32]);
    let tree = MerkleTree::from_leaves(vec![leaf]);
    assert_eq!(tree.depth(), 20);
    assert!(tree.verify(0, leaf, &tree.path(0).unwrap()));
    assert_eq!(tree.path(0).unwrap().nodes.len(), 20);
    assert_ne!(tree.root(), h_empty());
}

#[test]
fn build_bundle_outputs_fixed_size_rows_and_unique_salts() {
    let rows = (0u8..8)
        .map(|i| CsvRow {
            address: InMemoryKeystore::from_seed([i + 1; 32])
                .unwrap()
                .public_ed25519(),
            raw_amount: 100,
            bucket_id: 0,
        })
        .collect::<Vec<_>>();
    let bundle = build_bundle([9; 32], [10; 32], [11; 32], &rows).unwrap();
    assert_eq!(bundle.encrypted_rows.len(), 8);
    assert_eq!(bundle.encrypted_rows[0].version, 1);
    assert_eq!(bundle.encrypted_rows[0].ciphertext_plus_tag.len(), 741);
    assert_eq!(bundle.row_plaintexts_for_test.len(), 8);
    assert_ne!(
        bundle.row_plaintexts_for_test[0].salt,
        bundle.row_plaintexts_for_test[1].salt
    );
}

#[test]
fn build_bundle_rows_decrypt_with_wallet_converted_x25519_secret() {
    let ks = InMemoryKeystore::from_seed([42; 32]).unwrap();
    let rows = vec![CsvRow {
        address: ks.public_ed25519(),
        raw_amount: 100,
        bucket_id: 0,
    }];
    let bundle = build_bundle([9; 32], [10; 32], [0; 32], &rows).unwrap();
    let ctx = BundleContext {
        airdrop_id: bundle.airdrop_id,
        merkle_root: bundle.merkle_root,
        bucket_table_hash: bundle.bucket_table_hash,
    };
    let plain = ks
        .try_decrypt_row(ctx, bundle.encrypted_rows[0].clone())
        .expect("bundle row should decrypt for recipient wallet");
    assert_eq!(plain.address, ks.public_ed25519());
    assert_eq!(plain.bucket_id, 0);
}

#[test]
fn duplicate_salts_create_same_nullifier_for_different_addresses() {
    let salt = [99u8; 32];
    let a = LeafInput {
        address: [1; 32],
        bucket_id: 0,
        salt,
    };
    let b = LeafInput {
        address: [2; 32],
        bucket_id: 0,
        salt,
    };
    assert_ne!(
        distributionx_tree::leaf_hash(a),
        distributionx_tree::leaf_hash(b)
    );
    assert_eq!(h_null(a.salt), h_null(b.salt));
}
