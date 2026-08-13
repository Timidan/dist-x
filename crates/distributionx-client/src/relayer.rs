use distributionx_circuit::ClaimJournal;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RelayerSubmitRequest {
    pub airdrop_id: [u8; 32],
    pub nullifier: [u8; 32],
    pub receipt_bytes: Vec<u8>,
    #[serde(default)]
    pub journal: Option<ClaimJournal>,
    #[serde(default)]
    pub serialized_lez_tx: Vec<u8>,
    #[serde(default)]
    pub service_metadata: Option<String>,
}

impl RelayerSubmitRequest {
    pub fn new(airdrop_id: [u8; 32], nullifier: [u8; 32], receipt_bytes: Vec<u8>) -> Self {
        Self {
            airdrop_id,
            nullifier,
            receipt_bytes,
            journal: None,
            serialized_lez_tx: Vec::new(),
            service_metadata: None,
        }
    }

    pub fn new_with_claimant_built_tx(
        journal: ClaimJournal,
        receipt_bytes: Vec<u8>,
        serialized_lez_tx: Vec<u8>,
        service_metadata: Option<String>,
    ) -> Self {
        Self {
            airdrop_id: journal.airdrop_id,
            nullifier: journal.nullifier,
            receipt_bytes,
            journal: Some(journal),
            serialized_lez_tx,
            service_metadata,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RelayerSubmitResponse {
    pub tx_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_tx_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_block_id: Option<u64>,
}
