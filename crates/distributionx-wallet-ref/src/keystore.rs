use crate::sign::claim_message;
use crate::types::{BundleContext, DistributionXWalletError, EncryptedRowV1, RowPlaintext};
use ed25519_dalek::{Signer, SigningKey};
use secrecy::{ExposeSecret, Secret};
use zeroize::Zeroizing;

pub trait DistributionXKeystore {
    fn public_ed25519(&self) -> [u8; 32];
    fn public_x25519(&self) -> [u8; 32];
    fn sign_claim(&self, airdrop_id: [u8; 32], claim_destination_commitment: [u8; 32]) -> [u8; 64];
    fn try_decrypt_row(&self, ctx: BundleContext, row: EncryptedRowV1) -> Option<RowPlaintext>;
}

// Zeroization on drop is handled automatically by `Zeroizing<[u8; 32]>` and `Secret`'s own Drop.
// No explicit `impl Drop for InMemoryKeystore` is needed - adding one risks confusing readers
// into thinking the auto-derived behavior is missing.
pub struct InMemoryKeystore {
    seed: Secret<Zeroizing<[u8; 32]>>,
    signing_key: SigningKey,
}

impl InMemoryKeystore {
    pub fn from_seed(seed: [u8; 32]) -> Result<Self, DistributionXWalletError> {
        let signing_key = SigningKey::from_bytes(&seed);
        Ok(Self {
            seed: Secret::new(Zeroizing::new(seed)),
            signing_key,
        })
    }

    pub fn seed_for_test(&self) -> [u8; 32] {
        **self.seed.expose_secret()
    }
}

impl DistributionXKeystore for InMemoryKeystore {
    fn public_ed25519(&self) -> [u8; 32] {
        self.signing_key.verifying_key().to_bytes()
    }

    fn public_x25519(&self) -> [u8; 32] {
        crate::crypto::ed25519_public_to_x25519(self.public_ed25519()).unwrap_or([0; 32])
    }

    fn sign_claim(&self, airdrop_id: [u8; 32], claim_destination_commitment: [u8; 32]) -> [u8; 64] {
        self.signing_key
            .sign(&claim_message(airdrop_id, claim_destination_commitment))
            .to_bytes()
    }

    fn try_decrypt_row(&self, ctx: BundleContext, row: EncryptedRowV1) -> Option<RowPlaintext> {
        let x25519_sk =
            crate::crypto::ed25519_seed_to_x25519_secret(**self.seed.expose_secret()).ok()?;
        crate::decrypt::decrypt_row_with_x25519_secret(ctx, row, x25519_sk).ok()
    }
}

pub struct KeychainKeystore {
    inner: InMemoryKeystore,
}

impl KeychainKeystore {
    pub fn from_loaded_seed(seed: [u8; 32]) -> Result<Self, DistributionXWalletError> {
        Ok(Self {
            inner: InMemoryKeystore::from_seed(seed)?,
        })
    }
}

impl DistributionXKeystore for KeychainKeystore {
    fn public_ed25519(&self) -> [u8; 32] {
        self.inner.public_ed25519()
    }

    fn public_x25519(&self) -> [u8; 32] {
        self.inner.public_x25519()
    }

    fn sign_claim(&self, airdrop_id: [u8; 32], claim_destination_commitment: [u8; 32]) -> [u8; 64] {
        self.inner
            .sign_claim(airdrop_id, claim_destination_commitment)
    }

    fn try_decrypt_row(&self, ctx: BundleContext, row: EncryptedRowV1) -> Option<RowPlaintext> {
        self.inner.try_decrypt_row(ctx, row)
    }
}
