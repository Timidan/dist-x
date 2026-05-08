use serde::{Deserialize, Serialize};
use std::fmt;
use zeroize::Zeroize;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MerklePathNode {
    pub sibling: [u8; 32],
    pub is_right: bool,
}

impl MerklePathNode {
    pub const LEN: usize = 33;
}

#[derive(Clone, PartialEq, Eq, Zeroize, Serialize, Deserialize)]
pub struct RowPlaintext {
    pub address: [u8; 32],
    pub bucket_id: u8,
    pub salt: [u8; 32],
    pub merkle_path: [MerklePathNode; 20],
}

impl RowPlaintext {
    pub const LEN: usize = 725;
}

impl fmt::Debug for RowPlaintext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "RowPlaintext({})", crate::redacted::REDACTED)
    }
}

impl Zeroize for MerklePathNode {
    fn zeroize(&mut self) {
        self.sibling.zeroize();
        self.is_right = false;
    }
}

#[derive(Clone, PartialEq, Eq)]
pub struct EncryptedRowV1 {
    pub version: u8,
    pub row_index_le: [u8; 4],
    pub ephemeral_x25519_pk: [u8; 32],
    pub leaf: [u8; 32],
    pub ciphertext_plus_tag: [u8; 741],
}

impl EncryptedRowV1 {
    pub const LEN: usize = 810;
}

impl fmt::Debug for EncryptedRowV1 {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EncryptedRowV1")
            .field("version", &self.version)
            .field("row_index_le", &self.row_index_le)
            .field("ephemeral_x25519_pk", &self.ephemeral_x25519_pk)
            .field("leaf", &self.leaf)
            .field("ciphertext_plus_tag", &crate::redacted::REDACTED)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BundleContext {
    pub airdrop_id: [u8; 32],
    pub merkle_root: [u8; 32],
    pub bucket_table_hash: [u8; 32],
}

impl BundleContext {
    pub const HKDF_INFO_LEN: usize = 165;
    pub const AAD_LEN: usize = 232;
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DistributionXWalletError {
    #[error("invalid encrypted row version")]
    InvalidRowVersion,
    #[error("invalid plaintext length")]
    InvalidPlaintextLength,
    #[error("no decryptable row")]
    NoDecryptableRow,
    #[error("multiple decryptable rows")]
    MultipleDecryptableRows,
    #[error("key conversion failed")]
    KeyConversionFailed,
    #[error("keychain access failed")]
    KeychainAccessFailed,
    #[error("mnemonic import failed")]
    MnemonicImportFailed,
}
