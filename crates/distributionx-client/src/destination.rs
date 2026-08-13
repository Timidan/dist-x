use crate::types::DistributionXClientError;
use hmac::{Hmac, Mac};
use lee_core::{
    account::AccountId, encryption::ViewingPublicKey, NullifierPublicKey, NullifierSecretKey,
};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::{Digest, Sha256, Sha512};

pub const LEZ_VIEWING_PUBLIC_KEY_LEN: usize = ViewingPublicKey::LEN;
pub const DEFAULT_PRIVATE_ACCOUNT_IDENTIFIER: u128 = 0;

type HmacSha512 = Hmac<Sha512>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShieldedDestinationPacket {
    pub npk: [u8; 32],
    pub vpk: Vec<u8>,
    pub identifier_le: [u8; 16],
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShieldedDestination {
    pub packet: ShieldedDestinationPacket,
    pub secrets: ShieldedDestinationSecrets,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShieldedDestinationSecrets {
    pub secret_spending_key: [u8; 32],
    pub nullifier_secret_key: NullifierSecretKey,
    pub viewing_secret_key_d: [u8; 32],
    pub viewing_secret_key_z: [u8; 32],
}

#[derive(Serialize, Deserialize)]
struct ShieldedDestinationPacketJson {
    npk: String,
    vpk: String,
    identifier_le: String,
}

impl ShieldedDestinationPacket {
    pub fn from_json_slice(bytes: &[u8]) -> Result<Self, DistributionXClientError> {
        serde_json::from_slice(bytes)
            .map_err(|_| DistributionXClientError::InvalidDestinationPacket)
    }

    pub fn identifier(&self) -> u128 {
        u128::from_le_bytes(self.identifier_le)
    }
}

impl Serialize for ShieldedDestinationPacket {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        ShieldedDestinationPacketJson {
            npk: hex::encode(self.npk),
            vpk: hex::encode(&self.vpk),
            identifier_le: hex::encode(self.identifier_le),
        }
        .serialize(serializer)
    }
}

impl<'de> Deserialize<'de> for ShieldedDestinationPacket {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let json = ShieldedDestinationPacketJson::deserialize(deserializer)?;
        let npk = decode_fixed::<32, D::Error>(&json.npk, "npk")?;
        let identifier_le = decode_fixed::<16, D::Error>(&json.identifier_le, "identifier_le")?;
        let vpk = hex::decode(&json.vpk)
            .map_err(|_| serde::de::Error::custom("vpk must be a hex-encoded byte string"))?;
        if vpk.len() != LEZ_VIEWING_PUBLIC_KEY_LEN {
            return Err(serde::de::Error::custom(format!(
                "vpk must be {LEZ_VIEWING_PUBLIC_KEY_LEN} bytes"
            )));
        }
        Ok(Self {
            npk,
            vpk,
            identifier_le,
        })
    }
}

fn decode_fixed<const N: usize, E>(value: &str, field: &str) -> Result<[u8; N], E>
where
    E: serde::de::Error,
{
    let bytes =
        hex::decode(value).map_err(|_| E::custom(format!("{field} must be hex-encoded")))?;
    bytes
        .try_into()
        .map_err(|_| E::custom(format!("{field} must be {N} bytes")))
}

pub fn generate_shielded_destination() -> ShieldedDestination {
    let mut secret_spending_key = [0u8; 32];
    OsRng.fill_bytes(&mut secret_spending_key);
    derive_shielded_destination(secret_spending_key, DEFAULT_PRIVATE_ACCOUNT_IDENTIFIER)
}

pub fn derive_shielded_destination(
    secret_spending_key: [u8; 32],
    identifier: u128,
) -> ShieldedDestination {
    let nullifier_secret_key = derive_nullifier_secret_key(&secret_spending_key, None);
    let (viewing_secret_key_d, viewing_secret_key_z) =
        derive_viewing_secret_key(&secret_spending_key, None);
    let nullifier_public_key = NullifierPublicKey::from(&nullifier_secret_key);
    let viewing_public_key =
        ViewingPublicKey::from_seed(&viewing_secret_key_d, &viewing_secret_key_z);

    ShieldedDestination {
        packet: ShieldedDestinationPacket {
            npk: nullifier_public_key.0,
            vpk: viewing_public_key.to_bytes().to_vec(),
            identifier_le: identifier.to_le_bytes(),
        },
        secrets: ShieldedDestinationSecrets {
            secret_spending_key,
            nullifier_secret_key,
            viewing_secret_key_d,
            viewing_secret_key_z,
        },
    }
}

#[expect(
    clippy::big_endian_bytes,
    reason = "Matches the LEZ v0.2.4 key_protocol derivation"
)]
fn derive_nullifier_secret_key(
    secret_spending_key: &[u8; 32],
    index: Option<u32>,
) -> NullifierSecretKey {
    const PREFIX: &[u8; 8] = b"LEE/keys";
    const SUFFIX_1: &[u8; 1] = &[1];
    const SUFFIX_2: &[u8; 19] = &[0; 19];

    let index = index.unwrap_or(0);
    let mut hasher = Sha256::new();
    hasher.update(PREFIX);
    hasher.update(secret_spending_key);
    hasher.update(SUFFIX_1);
    hasher.update(index.to_be_bytes());
    hasher.update(SUFFIX_2);
    hasher.finalize().into()
}

#[expect(
    clippy::big_endian_bytes,
    reason = "Matches the LEZ v0.2.4 key_protocol derivation"
)]
fn derive_viewing_secret_key(
    secret_spending_key: &[u8; 32],
    index: Option<u32>,
) -> ([u8; 32], [u8; 32]) {
    const PREFIX: &[u8; 8] = b"LEE/keys";
    const SUFFIX_1: &[u8; 1] = &[2];
    const SUFFIX_2: &[u8; 19] = &[0; 19];

    let index = index.unwrap_or(0);
    let mut bytes = [0u8; 64];
    bytes[0..8].copy_from_slice(PREFIX);
    bytes[8..40].copy_from_slice(secret_spending_key);
    bytes[40..41].copy_from_slice(SUFFIX_1);
    bytes[41..45].copy_from_slice(&index.to_be_bytes());
    bytes[45..64].copy_from_slice(SUFFIX_2);

    let full_seed = hmac_sha512(&bytes, b"LEE_viewing_seed");
    let mut d = [0u8; 32];
    let mut z = [0u8; 32];
    d.copy_from_slice(&full_seed[..32]);
    z.copy_from_slice(&full_seed[32..]);
    (d, z)
}

fn hmac_sha512(message: &[u8], key: &[u8]) -> [u8; 64] {
    let mut mac = HmacSha512::new_from_slice(key).expect("HMAC-SHA512 accepts any key length");
    mac.update(message);
    mac.finalize().into_bytes().into()
}

pub fn compute_destination_commitment(
    packet: &ShieldedDestinationPacket,
) -> Result<[u8; 32], DistributionXClientError> {
    compute_private_account_id(packet.npk, &packet.vpk, packet.identifier())
}

pub fn compute_private_account_id(
    npk: [u8; 32],
    vpk: &[u8],
    identifier: u128,
) -> Result<[u8; 32], DistributionXClientError> {
    let viewing_public_key = ViewingPublicKey::from_bytes(vpk.to_vec())
        .map_err(|_| DistributionXClientError::InvalidDestinationPacket)?;
    Ok(*AccountId::from((&NullifierPublicKey(npk), &viewing_public_key, identifier)).value())
}
