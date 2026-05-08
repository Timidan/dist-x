use axum::{http::StatusCode, routing::post, Json, Router};
use distributionx_client::relayer::{RelayerSubmitRequest, RelayerSubmitResponse};

pub fn router() -> Router {
    Router::new().route("/v1/claim", post(handle_submit))
}

async fn handle_submit(
    Json(req): Json<RelayerSubmitRequest>,
) -> (StatusCode, Json<serde_json::Value>) {
    match crate::submit::submit_claim(req).await {
        Ok(RelayerSubmitResponse { tx_id }) => (
            StatusCode::OK,
            Json(serde_json::json!({ "status": "RELAYER_SUBMIT_OK", "tx_id": tx_id })),
        ),
        Err(err) => (
            StatusCode::BAD_REQUEST,
            Json(serde_json::json!({ "status": "RELAYER_SUBMIT_ERROR", "error": err.to_string() })),
        ),
    }
}
