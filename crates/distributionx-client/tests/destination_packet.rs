use distributionx_client::{compute_destination_commitment, ShieldedDestinationPacket};

#[test]
fn shielded_destination_packet_round_trips_as_hex_json() {
    let packet = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; 33],
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
fn destination_commitment_is_private_account_id_bound_to_npk() {
    let packet = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; 33],
        identifier_le: [3; 16],
    };
    let same = ShieldedDestinationPacket {
        npk: [1; 32],
        vpk: vec![2; 33],
        identifier_le: [3; 16],
    };
    let different = ShieldedDestinationPacket {
        npk: [4; 32],
        vpk: vec![2; 33],
        identifier_le: [3; 16],
    };
    assert_eq!(
        compute_destination_commitment(&packet),
        compute_destination_commitment(&same)
    );
    assert_ne!(
        compute_destination_commitment(&packet),
        compute_destination_commitment(&different)
    );
}
