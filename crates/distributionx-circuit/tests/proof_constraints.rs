use distributionx_circuit::{
    verify_claim_constraints, ClaimJournal, ClaimWitness, DistributionXCircuitError,
};
use distributionx_tree::{h_leaf, h_null, MerkleTree};
use distributionx_wallet_ref::{DistributionXKeystore, InMemoryKeystore};
use ed25519_dalek::{Signer, SigningKey};

#[test]
fn public_and_private_inputs_have_fixed_path_depth() {
    let journal = ClaimJournal::new([1; 32], [2; 32], 0, [3; 32], [4; 32]);
    let witness = ClaimWitness::empty_for_test();
    assert_eq!(journal.bucket_id, 0);
    assert_eq!(witness.merkle_path.len(), 20);
}

fn valid_case() -> (ClaimJournal, ClaimWitness) {
    let ks = InMemoryKeystore::from_seed([4; 32]).unwrap();
    let airdrop_id = [1; 32];
    let claim_destination_commitment = [2; 32];
    let salt = [3; 32];
    let leaf = h_leaf(ks.public_ed25519(), 1, salt);
    let tree = MerkleTree::from_leaves(vec![leaf]);
    let journal = ClaimJournal::new(
        airdrop_id,
        tree.root(),
        1,
        h_null(salt),
        claim_destination_commitment,
    );
    let witness = ClaimWitness {
        address: ks.public_ed25519(),
        salt,
        claim_sig: ks.sign_claim(airdrop_id, claim_destination_commitment),
        merkle_path: tree.path(0).unwrap().nodes,
    };
    (journal, witness)
}

#[test]
fn rejects_wrong_merkle_path() {
    let (journal, mut witness) = valid_case();
    witness.merkle_path[0].sibling[0] ^= 1;
    assert_eq!(
        verify_claim_constraints(&journal, &witness).unwrap_err(),
        DistributionXCircuitError::BadMerklePath
    );
}

#[test]
fn rejects_wrong_salt() {
    let (journal, mut witness) = valid_case();
    witness.salt[0] ^= 1;
    assert_eq!(
        verify_claim_constraints(&journal, &witness).unwrap_err(),
        DistributionXCircuitError::BadMerklePath
    );
}

#[test]
fn rejects_wrong_claim_destination_commitment() {
    let (mut journal, witness) = valid_case();
    journal.claim_destination_commitment[0] ^= 1;
    assert_eq!(
        verify_claim_constraints(&journal, &witness).unwrap_err(),
        DistributionXCircuitError::BadSignature
    );
}

#[test]
fn rejects_v1_claim_message_signature() {
    let (journal, mut witness) = valid_case();
    let mut v1_message = Vec::with_capacity("logos-distributionx/claim-v1".len() + 64);
    v1_message.extend_from_slice(b"logos-distributionx/claim-v1");
    v1_message.extend_from_slice(&journal.airdrop_id);
    v1_message.extend_from_slice(&journal.claim_destination_commitment);
    witness.claim_sig = SigningKey::from_bytes(&[4; 32])
        .sign(&v1_message)
        .to_bytes();
    assert_eq!(
        verify_claim_constraints(&journal, &witness).unwrap_err(),
        DistributionXCircuitError::BadSignature
    );
}

#[test]
fn rejects_wrong_bucket() {
    let (mut journal, witness) = valid_case();
    journal.bucket_id = 2;
    assert_eq!(
        verify_claim_constraints(&journal, &witness).unwrap_err(),
        DistributionXCircuitError::BadMerklePath
    );
}
