use crate::types::{DistributionDraft, DistributionXClientError};
use distributionx_tree::{
    airdrop_id, bucket_table_hash, build_bundle_with_airdrop_id, parse_csv, BundleV1,
};

#[derive(Clone, Debug)]
pub struct DistributionBuild {
    pub draft: DistributionDraft,
    pub airdrop_id: [u8; 32],
    pub bucket_table: Vec<u64>,
    pub bundle: BundleV1,
}

pub fn build_distribution(
    draft: DistributionDraft,
    csv: &str,
    token_id: [u8; 32],
    merkle_root_hint: [u8; 32],
    expiry_unix: u64,
    recovery_address: [u8; 32],
    nonce: u64,
) -> Result<DistributionBuild, DistributionXClientError> {
    let parsed = parse_csv(csv).map_err(|_| DistributionXClientError::InvalidDraftName)?;
    let table_hash = bucket_table_hash(&parsed.bucket_table);
    let bundle =
        build_bundle_with_airdrop_id(table_hash, merkle_root_hint, &parsed.rows, |merkle_root| {
            airdrop_id(
                draft.distributor,
                token_id,
                merkle_root,
                table_hash,
                expiry_unix,
                recovery_address,
                nonce,
            )
        })
        .map_err(|_| DistributionXClientError::InvalidDraftName)?;
    let aid = bundle.airdrop_id;
    Ok(DistributionBuild {
        draft,
        airdrop_id: aid,
        bucket_table: parsed.bucket_table,
        bundle,
    })
}
