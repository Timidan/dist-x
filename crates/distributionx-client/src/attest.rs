use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SelfDisclosure {
    pub airdrop_id: [u8; 32],
    pub merkle_root: [u8; 32],
    pub bucket_table: Vec<u64>,
    pub population_per_bucket: Vec<usize>,
    pub csv_hash: [u8; 32],
    pub dedup_count: usize,
    pub canonical_count: usize,
    pub salt_csprng_seed_hash: [u8; 32],
    pub csprng_provider: String,
    pub attestation_version: String,
}

impl SelfDisclosure {
    pub fn for_test() -> Self {
        Self {
            airdrop_id: [1; 32],
            merkle_root: [2; 32],
            bucket_table: vec![100],
            population_per_bucket: vec![8],
            csv_hash: [3; 32],
            dedup_count: 8,
            canonical_count: 8,
            salt_csprng_seed_hash: [4; 32],
            csprng_provider: "OsRng".into(),
            attestation_version: "v1".into(),
        }
    }
}
