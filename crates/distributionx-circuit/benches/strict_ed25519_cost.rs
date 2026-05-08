use criterion::{criterion_group, criterion_main, Criterion};
use distributionx_circuit::verify_claim_constraints;
use distributionx_tree::{h_leaf, h_null, MerkleTree};
use distributionx_wallet_ref::{DistributionXKeystore, InMemoryKeystore};

fn bench_strict_ed25519_and_path(c: &mut Criterion) {
    let ks = InMemoryKeystore::from_seed([7; 32]).unwrap();
    let salt = [8; 32];
    let airdrop_id = [9; 32];
    let claim_destination_commitment = [10; 32];
    let tree = MerkleTree::from_leaves(vec![h_leaf(ks.public_ed25519(), 0, salt)]);
    let journal = distributionx_circuit::ClaimJournal::new(
        airdrop_id,
        tree.root(),
        0,
        h_null(salt),
        claim_destination_commitment,
    );
    let witness = distributionx_circuit::ClaimWitness {
        address: ks.public_ed25519(),
        salt,
        claim_sig: ks.sign_claim(airdrop_id, claim_destination_commitment),
        merkle_path: tree.path(0).unwrap().nodes,
    };
    c.bench_function("strict_ed25519_plus_merkle_path", |b| {
        b.iter(|| verify_claim_constraints(&journal, &witness).unwrap())
    });
}

criterion_group!(benches, bench_strict_ed25519_and_path);
criterion_main!(benches);
