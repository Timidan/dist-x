use crate::types::DistributionXWalletError;
use ed25519_dalek::SigningKey;
use libsodium_sys::{crypto_sign_ed25519_pk_to_curve25519, crypto_sign_ed25519_sk_to_curve25519};
use zeroize::Zeroize;

pub fn ed25519_public_to_x25519(pubkey: [u8; 32]) -> Result<[u8; 32], DistributionXWalletError> {
    let mut out = [0u8; 32];
    let rc = unsafe { crypto_sign_ed25519_pk_to_curve25519(out.as_mut_ptr(), pubkey.as_ptr()) };
    if rc == 0 {
        Ok(out)
    } else {
        Err(DistributionXWalletError::KeyConversionFailed)
    }
}

pub fn ed25519_seed_to_x25519_secret(seed: [u8; 32]) -> Result<[u8; 32], DistributionXWalletError> {
    let signing_key = SigningKey::from_bytes(&seed);
    let public_key = signing_key.verifying_key().to_bytes();
    let mut ed25519_secret_key = [0u8; 64];
    ed25519_secret_key[..32].copy_from_slice(&seed);
    ed25519_secret_key[32..].copy_from_slice(&public_key);

    let mut out = [0u8; 32];
    let rc = unsafe {
        crypto_sign_ed25519_sk_to_curve25519(out.as_mut_ptr(), ed25519_secret_key.as_ptr())
    };
    ed25519_secret_key.zeroize();

    if rc == 0 {
        Ok(out)
    } else {
        Err(DistributionXWalletError::KeyConversionFailed)
    }
}
