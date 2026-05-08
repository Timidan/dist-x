use distributionx_client::relayer::RelayerSubmitRequest;
use distributionx_relayer_ref::config::RelayerConfig;
use distributionx_relayer_ref::http::router;
use distributionx_relayer_ref::submit::submit_claim;

#[test]
fn default_config_has_no_on_chain_fee() {
    let cfg = RelayerConfig::default();
    assert_eq!(cfg.fee_lamports, 0);
    assert_eq!(cfg.bind_addr, "127.0.0.1:8787");
}

#[tokio::test]
async fn submit_claim_uses_configured_testnet_submitter() {
    std::env::set_var(
        "DISTRIBUTIONX_RELAYER_SUBMIT_COMMAND",
        "cat >/dev/null; printf '{\"tx_id\":\"testnet-tx-123\"}'",
    );
    let mut req = RelayerSubmitRequest::new([1; 32], [2; 32], vec![3]);
    req.serialized_lez_tx = vec![4, 5, 6];
    let resp = submit_claim(req).await.unwrap();
    assert_eq!(resp.tx_id, "testnet-tx-123");
    std::env::remove_var("DISTRIBUTIONX_RELAYER_SUBMIT_COMMAND");
}

#[test]
fn router_builds() {
    let _ = router();
}
