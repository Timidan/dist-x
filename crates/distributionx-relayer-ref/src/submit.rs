use distributionx_client::relayer::{RelayerSubmitRequest, RelayerSubmitResponse};
use std::io::Write;
use std::process::{Command, Stdio};

#[derive(Debug, thiserror::Error)]
pub enum RelayerError {
    #[error("empty receipt")]
    EmptyReceipt,
    #[error("empty serialized LEZ transaction")]
    EmptySerializedLezTx,
    #[error("DISTRIBUTIONX_RELAYER_SUBMIT_COMMAND is not set")]
    MissingSubmitCommand,
    #[error("relayer submit command failed")]
    SubmitCommandFailed,
    #[error("relayer submit command returned invalid JSON")]
    InvalidSubmitResponse,
}

pub async fn submit_claim(
    req: RelayerSubmitRequest,
) -> Result<RelayerSubmitResponse, RelayerError> {
    if req.receipt_bytes.is_empty() {
        return Err(RelayerError::EmptyReceipt);
    }
    if req.serialized_lez_tx.is_empty() {
        return Err(RelayerError::EmptySerializedLezTx);
    }

    let command = std::env::var("DISTRIBUTIONX_RELAYER_SUBMIT_COMMAND")
        .map_err(|_| RelayerError::MissingSubmitCommand)?;
    let mut child = Command::new("bash")
        .arg("-c")
        .arg(command)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|_| RelayerError::SubmitCommandFailed)?;

    let input = serde_json::to_vec(&req).map_err(|_| RelayerError::InvalidSubmitResponse)?;
    child
        .stdin
        .as_mut()
        .ok_or(RelayerError::SubmitCommandFailed)?
        .write_all(&input)
        .map_err(|_| RelayerError::SubmitCommandFailed)?;

    let output = child
        .wait_with_output()
        .map_err(|_| RelayerError::SubmitCommandFailed)?;
    if !output.status.success() {
        return Err(RelayerError::SubmitCommandFailed);
    }
    let response: RelayerSubmitResponse =
        serde_json::from_slice(&output.stdout).map_err(|_| RelayerError::InvalidSubmitResponse)?;
    if response.tx_id.trim().is_empty() {
        return Err(RelayerError::InvalidSubmitResponse);
    }
    Ok(response)
}
