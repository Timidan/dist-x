use distributionx_circuit::ClaimJournal;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProofArtifact {
    pub journal: ClaimJournal,
    pub receipt_bytes: Vec<u8>,
}
