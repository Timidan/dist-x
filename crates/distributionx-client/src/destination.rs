use crate::types::DistributionXClientError;
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use sha2::{Digest, Sha256};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ShieldedDestinationPacket {
    pub npk: [u8; 32],
    pub vpk: Vec<u8>,
    pub identifier_le: [u8; 16],
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
        if vpk.is_empty() {
            return Err(serde::de::Error::custom("vpk must not be empty"));
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

pub fn compute_destination_commitment(packet: &ShieldedDestinationPacket) -> [u8; 32] {
    const PRIVATE_ACCOUNT_ID_PREFIX: &[u8; 32] = b"/LEE/v0.3/AccountId/Private/\x00\x00\x00\x00";

    let mut hasher = Sha256::new();
    hasher.update(PRIVATE_ACCOUNT_ID_PREFIX);
    hasher.update(packet.npk);
    hasher.finalize().into()
}
