#[cfg(feature = "host")]
mod crypto;
#[cfg(feature = "host")]
mod decrypt;
#[cfg(feature = "host")]
mod keystore;
mod redacted;
mod sign;
#[cfg(feature = "host")]
pub mod storage;
mod types;

#[cfg(feature = "host")]
pub use crypto::{ed25519_public_to_x25519, ed25519_seed_to_x25519_secret};
#[cfg(feature = "host")]
pub use decrypt::{
    aad as bundle_aad, decrypt_row_with_x25519_secret, derive_aead_key_nonce,
    hkdf_info as bundle_hkdf_info, trial_decrypt_bundle,
};
#[cfg(feature = "host")]
pub use keystore::{DistributionXKeystore, InMemoryKeystore, KeychainKeystore};
pub use sign::claim_message;
pub use types::{
    BundleContext, DistributionXWalletError, EncryptedRowV1, MerklePathNode, RowPlaintext,
};
