use crate::{ClaimJournal, ClaimWitness};
use distributionx_tree::{h_leaf, h_node, h_null};
use distributionx_wallet_ref::claim_message;
use ed25519_consensus::{Signature, VerificationKey};

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DistributionXCircuitError {
    #[error("bad signature")]
    BadSignature,
    #[error("bad merkle path")]
    BadMerklePath,
    #[error("bad nullifier")]
    BadNullifier,
    #[error("bad path depth")]
    BadPathDepth,
}

pub fn verify_claim_constraints(
    journal: &ClaimJournal,
    witness: &ClaimWitness,
) -> Result<(), DistributionXCircuitError> {
    let key = VerificationKey::try_from(witness.address)
        .map_err(|_| DistributionXCircuitError::BadSignature)?;
    let signature = Signature::from(witness.claim_sig);
    key.verify(
        &signature,
        &claim_message(journal.airdrop_id, journal.claim_destination_commitment),
    )
    .map_err(|_| DistributionXCircuitError::BadSignature)?;

    if witness.merkle_path.len() != 20 {
        return Err(DistributionXCircuitError::BadPathDepth);
    }

    let mut cur = h_leaf(witness.address, journal.bucket_id, witness.salt);
    for node in &witness.merkle_path {
        // Mirrors distributionx-tree: is_right is true when the current node is the right child.
        cur = if node.is_right {
            h_node(node.sibling, cur)
        } else {
            h_node(cur, node.sibling)
        };
    }
    if cur != journal.merkle_root {
        return Err(DistributionXCircuitError::BadMerklePath);
    }

    if h_null(witness.salt) != journal.nullifier {
        return Err(DistributionXCircuitError::BadNullifier);
    }

    Ok(())
}
