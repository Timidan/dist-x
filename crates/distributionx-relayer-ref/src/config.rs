#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RelayerConfig {
    pub bind_addr: String,
    pub rpc_url: String,
    pub fee_lamports: u64,
}

impl Default for RelayerConfig {
    fn default() -> Self {
        Self {
            bind_addr: "127.0.0.1:8787".into(),
            rpc_url: "http://127.0.0.1:8899".into(),
            fee_lamports: 0,
        }
    }
}
