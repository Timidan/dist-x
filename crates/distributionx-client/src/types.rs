#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DistributionXClientError {
    #[error("invalid draft name")]
    InvalidDraftName,
    #[error("no eligible row for wallet")]
    NoEligibleRow,
    #[error("proof generation failed")]
    ProofGenerationFailed,
    #[error("relayer submission failed")]
    RelayerSubmissionFailed,
    #[error("invalid destination commitment")]
    InvalidDestinationCommitment,
    #[error("invalid shielded destination packet")]
    InvalidDestinationPacket,
    #[error("unsupported shielded mint primitive")]
    UnsupportedShieldedMintPrimitive,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DistributionDraft {
    pub name: String,
    pub distributor: [u8; 32],
}

impl DistributionDraft {
    pub fn new(
        name: impl Into<String>,
        distributor: [u8; 32],
    ) -> Result<Self, DistributionXClientError> {
        let name = name.into();
        if name.trim().is_empty() {
            return Err(DistributionXClientError::InvalidDraftName);
        }
        Ok(Self { name, distributor })
    }
}
