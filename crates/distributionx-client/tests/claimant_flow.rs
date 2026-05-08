use distributionx_client::prepare_claim;
use distributionx_client::relayer::{RelayerSubmitRequest, RelayerSubmitResponse};
use distributionx_tree::{build_bundle, CsvRow};
use distributionx_wallet_ref::{DistributionXKeystore, InMemoryKeystore};

#[test]
fn prepare_claim_fails_before_storing_seed_when_no_row_decrypts() {
    let rows = (0u8..8)
        .map(|i| {
            let ks = InMemoryKeystore::from_seed([i + 1; 32]).unwrap();
            CsvRow {
                address: ks.public_ed25519(),
                raw_amount: 100,
                bucket_id: 0,
            }
        })
        .collect::<Vec<_>>();
    let bundle = build_bundle([1; 32], [2; 32], [0; 32], &rows).unwrap();
    let wallet = InMemoryKeystore::from_seed([99; 32]).unwrap();
    let err = prepare_claim(&wallet, &bundle, [5; 32]).unwrap_err();
    assert_eq!(err.to_string(), "no eligible row for wallet");
}

#[test]
fn relayer_payload_contains_no_salt() {
    let req = RelayerSubmitRequest::new([1; 32], [2; 32], vec![3]);
    let encoded = serde_json::to_string(&req).unwrap();
    assert!(encoded.contains("airdrop_id"));
    assert!(encoded.contains("receipt_bytes"));
    assert!(!encoded.contains("salt"));
    let resp = RelayerSubmitResponse {
        tx_id: "tx123".into(),
    };
    assert_eq!(resp.tx_id, "tx123");
}
