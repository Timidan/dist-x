use distributionx_circuit::{verify_claim_constraints, ClaimJournal, ClaimWitness};
use distributionx_tree::{h_leaf, h_null, MerkleTree};
use distributionx_wallet_ref::{DistributionXKeystore, InMemoryKeystore};

#[test]
fn strict_signature_accepts_pinned_wallet_output_and_rejects_tamper() {
    let ks = InMemoryKeystore::from_seed([8; 32]).unwrap();
    let airdrop_id = [1; 32];
    let claim_destination_commitment = [2; 32];
    let salt = [3; 32];
    let leaf = h_leaf(ks.public_ed25519(), 0, salt);
    let tree = MerkleTree::from_leaves(vec![leaf]);
    let sig = ks.sign_claim(airdrop_id, claim_destination_commitment);
    let journal = ClaimJournal::new(
        airdrop_id,
        tree.root(),
        0,
        h_null(salt),
        claim_destination_commitment,
    );
    let witness = ClaimWitness {
        address: ks.public_ed25519(),
        salt,
        claim_sig: sig,
        merkle_path: tree.path(0).unwrap().nodes,
    };
    verify_claim_constraints(&journal, &witness).unwrap();

    let mut bad = witness.clone();
    bad.claim_sig[0] ^= 1;
    assert!(verify_claim_constraints(&journal, &bad).is_err());
}
