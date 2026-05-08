pub fn claim_message(airdrop_id: [u8; 32], claim_destination_commitment: [u8; 32]) -> Vec<u8> {
    let mut msg = Vec::with_capacity("logos-distributionx/claim-v2".len() + 64);
    msg.extend_from_slice(b"logos-distributionx/claim-v2");
    msg.extend_from_slice(&airdrop_id);
    msg.extend_from_slice(&claim_destination_commitment);
    msg
}
