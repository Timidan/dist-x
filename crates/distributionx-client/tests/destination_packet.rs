use distributionx_client::{
    compute_destination_commitment, derive_shielded_destination, generate_shielded_destination,
    ShieldedDestinationPacket, LEZ_VIEWING_PUBLIC_KEY_LEN,
};
use lee_core::{account::AccountId, encryption::ViewingPublicKey, NullifierPublicKey};

#[test]
fn shielded_destination_packet_round_trips_as_hex_json() {
    let packet = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; LEZ_VIEWING_PUBLIC_KEY_LEN],
        identifier_le: [3; 16],
    };
    let json = serde_json::to_string(&packet).unwrap();
    assert!(json.contains("\"npk\""));
    assert!(json.contains("\"vpk\""));
    assert!(json.contains("\"identifier_le\""));
    let decoded: ShieldedDestinationPacket = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded, packet);
}

#[test]
fn shielded_destination_packet_rejects_non_ml_kem_viewing_public_key() {
    let json = serde_json::json!({
        "npk": hex::encode([1u8; 32]),
        "vpk": hex::encode([2u8; 33]),
        "identifier_le": hex::encode([3u8; 16])
    });

    let err = serde_json::from_value::<ShieldedDestinationPacket>(json).unwrap_err();

    assert!(
        err.to_string().contains("vpk must be 1184 bytes"),
        "unexpected error: {err}",
    );
}

#[test]
fn generated_shielded_destination_uses_lez_private_account_keys() {
    let destination = generate_shielded_destination();

    assert_eq!(destination.packet.vpk.len(), LEZ_VIEWING_PUBLIC_KEY_LEN);
    assert_ne!(destination.packet.npk, [0u8; 32]);
    assert_ne!(destination.secrets.secret_spending_key, [0u8; 32]);
    assert_ne!(destination.secrets.nullifier_secret_key, [0u8; 32]);
    assert_ne!(destination.secrets.viewing_secret_key_d, [0u8; 32]);
    assert_ne!(destination.secrets.viewing_secret_key_z, [0u8; 32]);
    assert_ne!(
        compute_destination_commitment(&destination.packet).unwrap(),
        [0u8; 32],
    );
}

#[test]
fn generated_destination_matches_local_submit_private_foreign_deserialization() {
    let destination = generate_shielded_destination();
    let packet = destination.packet;
    let parsed_vpk =
        ViewingPublicKey::from_bytes(packet.vpk.clone()).expect("LEZ ML-KEM viewing public key");
    let recipient = AccountId::from((
        &NullifierPublicKey(packet.npk),
        &parsed_vpk,
        packet.identifier(),
    ));

    assert_eq!(parsed_vpk.to_bytes().len(), LEZ_VIEWING_PUBLIC_KEY_LEN);
    assert_eq!(
        compute_destination_commitment(&packet).unwrap(),
        *recipient.value()
    );
}

#[test]
fn destination_derivation_matches_lez_v0_2_4_key_protocol_vector() {
    let secret_spending_key = [
        246, 79, 26, 124, 135, 95, 52, 51, 201, 27, 48, 194, 2, 144, 51, 219, 245, 128, 139, 222,
        42, 195, 105, 33, 115, 97, 186, 0, 97, 14, 218, 191,
    ];
    let destination = derive_shielded_destination(secret_spending_key, 0);

    assert_eq!(
        destination.secrets.nullifier_secret_key,
        [
            154, 102, 103, 5, 34, 235, 227, 13, 22, 182, 226, 11, 7, 67, 110, 162, 99, 193, 174,
            34, 234, 19, 222, 2, 22, 12, 163, 252, 88, 11, 0, 163,
        ]
    );
    assert_eq!(
        destination.packet.npk,
        [
            7, 123, 125, 191, 233, 183, 201, 4, 20, 214, 155, 210, 45, 234, 27, 240, 194, 111, 97,
            247, 155, 113, 122, 246, 192, 0, 70, 61, 76, 71, 70, 2,
        ]
    );
    assert_eq!(
        destination.secrets.viewing_secret_key_d,
        [
            187, 143, 146, 12, 68, 148, 25, 203, 21, 92, 131, 2, 221, 81, 117, 62, 98, 194, 159,
            177, 102, 254, 236, 182, 76, 242, 116, 219, 17, 166, 99, 36,
        ]
    );
    assert_eq!(
        destination.secrets.viewing_secret_key_z,
        [
            80, 97, 83, 209, 145, 99, 168, 99, 89, 29, 153, 236, 82, 99, 134, 114, 168, 19, 223,
            69, 34, 47, 76, 76, 15, 97, 245, 184, 25, 103, 251, 82,
        ]
    );
    assert_eq!(destination.packet.vpk.len(), LEZ_VIEWING_PUBLIC_KEY_LEN);
}

#[test]
fn destination_commitment_is_private_account_id_bound_to_npk() {
    let packet = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; LEZ_VIEWING_PUBLIC_KEY_LEN],
        identifier_le: [3; 16],
    };
    let same = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; LEZ_VIEWING_PUBLIC_KEY_LEN],
        identifier_le: [3; 16],
    };
    let different = ShieldedDestinationPacket {
        npk: [4; 32],
        vpk: vec![2; LEZ_VIEWING_PUBLIC_KEY_LEN],
        identifier_le: [3; 16],
    };
    let different_identifier = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; LEZ_VIEWING_PUBLIC_KEY_LEN],
        identifier_le: [4; 16],
    };
    let different_viewing_key = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![5; LEZ_VIEWING_PUBLIC_KEY_LEN],
        identifier_le: [3; 16],
    };
    assert_eq!(
        compute_destination_commitment(&packet).unwrap(),
        compute_destination_commitment(&same).unwrap()
    );
    assert_ne!(
        compute_destination_commitment(&packet).unwrap(),
        compute_destination_commitment(&different).unwrap()
    );
    assert_ne!(
        compute_destination_commitment(&packet).unwrap(),
        compute_destination_commitment(&different_identifier).unwrap()
    );
    assert_ne!(
        compute_destination_commitment(&packet).unwrap(),
        compute_destination_commitment(&different_viewing_key).unwrap()
    );
}

#[test]
fn destination_commitment_rejects_an_invalid_viewing_key_length() {
    let packet = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; 33],
        identifier_le: [3; 16],
    };

    assert_eq!(
        compute_destination_commitment(&packet),
        Err(distributionx_client::DistributionXClientError::InvalidDestinationPacket)
    );
}
