use crate::types::DistributionXWalletError;
use bip39::Mnemonic;
use sha2::{Digest, Sha256};

pub struct KeychainSeedStore {
    account: String,
}

impl KeychainSeedStore {
    pub fn new(account: impl Into<String>) -> Self {
        Self {
            account: account.into(),
        }
    }

    pub fn service_name(&self) -> &'static str {
        "logos-distributionx-wallet-ref"
    }

    pub fn account_name(&self) -> &str {
        &self.account
    }

    pub fn save_seed(&self, seed: [u8; 32]) -> Result<(), DistributionXWalletError> {
        let entry = keyring::Entry::new(self.service_name(), self.account_name())
            .map_err(|_| DistributionXWalletError::KeychainAccessFailed)?;
        entry
            .set_password(&hex_encode(seed))
            .map_err(|_| DistributionXWalletError::KeychainAccessFailed)
    }

    pub fn load_seed(&self) -> Result<[u8; 32], DistributionXWalletError> {
        let entry = keyring::Entry::new(self.service_name(), self.account_name())
            .map_err(|_| DistributionXWalletError::KeychainAccessFailed)?;
        let encoded = entry
            .get_password()
            .map_err(|_| DistributionXWalletError::KeychainAccessFailed)?;
        hex_decode_32(&encoded).ok_or(DistributionXWalletError::KeychainAccessFailed)
    }
}

pub fn seed_from_mnemonic_for_test(phrase: &str) -> Result<[u8; 32], DistributionXWalletError> {
    let mnemonic =
        Mnemonic::parse(phrase).map_err(|_| DistributionXWalletError::MnemonicImportFailed)?;
    let full_seed = mnemonic.to_seed("");
    let digest: [u8; 32] = Sha256::digest(full_seed).into();
    Ok(digest)
}

fn hex_encode(bytes: [u8; 32]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(64);
    for b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

fn hex_decode_32(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 {
        return None;
    }
    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}
