use distributionx_wallet_ref::MerklePathNode;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClaimWitness {
    pub address: [u8; 32],
    pub salt: [u8; 32],
    #[serde(with = "sig64")]
    pub claim_sig: [u8; 64],
    pub merkle_path: Vec<MerklePathNode>,
}

impl ClaimWitness {
    pub fn empty_for_test() -> Self {
        Self {
            address: [0; 32],
            salt: [0; 32],
            claim_sig: [0; 64],
            merkle_path: vec![MerklePathNode::default(); 20],
        }
    }
}

mod sig64 {
    use serde::de::{Error, Visitor};
    use serde::{Deserializer, Serializer};
    use std::fmt;

    pub fn serialize<S>(value: &[u8; 64], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_bytes(value)
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<[u8; 64], D::Error>
    where
        D: Deserializer<'de>,
    {
        struct SigVisitor;

        impl<'de> Visitor<'de> for SigVisitor {
            type Value = [u8; 64];

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a 64-byte Ed25519 signature")
            }

            fn visit_bytes<E>(self, value: &[u8]) -> Result<Self::Value, E>
            where
                E: Error,
            {
                value
                    .try_into()
                    .map_err(|_| E::invalid_length(value.len(), &self))
            }

            fn visit_seq<A>(self, mut seq: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::SeqAccess<'de>,
            {
                let mut out = [0u8; 64];
                for (index, byte) in out.iter_mut().enumerate() {
                    *byte = seq
                        .next_element()?
                        .ok_or_else(|| Error::invalid_length(index, &self))?;
                }
                Ok(out)
            }
        }

        deserializer.deserialize_bytes(SigVisitor)
    }
}
