use crate::proof::ProofArtifact;
use crate::types::DistributionXClientError;
use distributionx_circuit::{verify_claim_constraints, ClaimJournal, ClaimWitness};
use distributionx_tree::{h_null, BundleV1};
use distributionx_wallet_ref::{BundleContext, DistributionXKeystore};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PreparedClaim {
    pub proof: ProofArtifact,
    pub amount_bucket: u8,
    pub witness: ClaimWitness,
}

pub fn prepare_claim<K: DistributionXKeystore>(
    keystore: &K,
    bundle: &BundleV1,
    claim_destination_commitment: [u8; 32],
) -> Result<PreparedClaim, DistributionXClientError> {
    let ctx = BundleContext {
        airdrop_id: bundle.airdrop_id,
        merkle_root: bundle.merkle_root,
        bucket_table_hash: bundle.bucket_table_hash,
    };
    let mut found = None;
    for row in bundle.encrypted_rows.clone() {
        if let Some(plain) = keystore.try_decrypt_row(ctx, row) {
            if found.is_some() {
                return Err(DistributionXClientError::NoEligibleRow);
            }
            found = Some(plain);
        }
    }
    let plain = found.ok_or(DistributionXClientError::NoEligibleRow)?;
    let journal = ClaimJournal::new(
        bundle.airdrop_id,
        bundle.merkle_root,
        plain.bucket_id,
        h_null(plain.salt),
        claim_destination_commitment,
    );
    let witness = ClaimWitness {
        address: plain.address,
        salt: plain.salt,
        claim_sig: keystore.sign_claim(bundle.airdrop_id, claim_destination_commitment),
        merkle_path: plain.merkle_path.to_vec(),
    };
    verify_claim_constraints(&journal, &witness)
        .map_err(|_| DistributionXClientError::ProofGenerationFailed)?;
    let receipt_bytes = serde_json::to_vec(&journal)
        .map_err(|_| DistributionXClientError::ProofGenerationFailed)?;
    Ok(PreparedClaim {
        proof: ProofArtifact {
            journal,
            receipt_bytes,
        },
        amount_bucket: plain.bucket_id,
        witness,
    })
}
