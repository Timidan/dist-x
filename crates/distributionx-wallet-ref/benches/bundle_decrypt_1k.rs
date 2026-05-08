use criterion::{criterion_group, criterion_main, Criterion};
use distributionx_wallet_ref::{trial_decrypt_bundle, BundleContext, EncryptedRowV1};

fn bench_bundle_decrypt_1k(c: &mut Criterion) {
    let ctx = BundleContext {
        airdrop_id: [1; 32],
        merkle_root: [2; 32],
        bucket_table_hash: [3; 32],
    };
    let rows = vec![
        EncryptedRowV1 {
            version: 1,
            row_index_le: 0u32.to_le_bytes(),
            ephemeral_x25519_pk: [4; 32],
            leaf: [5; 32],
            ciphertext_plus_tag: [6; 741],
        };
        1000
    ];
    c.bench_function("bundle_decrypt_1k_all_fail", |b| {
        b.iter(|| {
            let _ = trial_decrypt_bundle(ctx, rows.clone(), [7; 32]);
        });
    });
}

criterion_group!(benches, bench_bundle_decrypt_1k);
criterion_main!(benches);
