use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "distributionx",
    about = "Private allowlist distribution CLI for LEZ"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    #[command(about = "Initialize a distribution from an eligibility CSV")]
    Init {
        #[arg(long, value_name = "PATH", help = "Eligibility CSV path")]
        csv: String,
        #[arg(long, value_name = "PUBLIC_KEY", help = "Distributor LEZ account")]
        distributor: String,
        #[arg(long, value_name = "TOKEN_ID", help = "Token id to distribute")]
        token: String,
        #[arg(
            long = "token-source-account",
            value_name = "ACCOUNT",
            help = "Token holding account that funds custom-token claim settlement"
        )]
        token_source_account: Option<String>,
        #[arg(long, value_name = "URL", help = "LEZ RPC URL")]
        rpc: String,
        #[arg(long, value_name = "UNIX_SECONDS", help = "Distribution expiry")]
        expiry: u64,
        #[arg(long, value_name = "PUBLIC_KEY", help = "Recovery account")]
        recovery: String,
    },
    #[command(about = "Fund an initialized distribution")]
    Fund {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
        #[arg(long, value_name = "TOKENS", help = "Token amount")]
        amount: u64,
    },
    #[command(about = "Query an account token balance")]
    QueryTokenBalance {
        #[arg(long, value_name = "URL", help = "LEZ RPC URL")]
        rpc: String,
        #[arg(long, value_name = "PUBLIC_KEY", help = "Account to query")]
        account: String,
        #[arg(long, value_name = "TOKEN_ID", help = "Token id")]
        token: String,
    },
    #[command(about = "Generate a private membership proof for a claimant")]
    Prove {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
        #[arg(long, value_name = "PATH", help = "Distribution bundle JSON")]
        bundle: String,
        #[arg(long, value_name = "PATH", help = "Claim wallet seed file")]
        wallet: String,
        #[arg(
            long = "destination-packet",
            value_name = "PATH",
            help = "Shielded destination JSON"
        )]
        destination_packet: Option<String>,
        #[arg(
            long = "claim-destination-commitment",
            value_name = "HEX",
            help = "Destination commitment hex"
        )]
        claim_destination_commitment: Option<String>,
    },
    #[command(about = "Prepare a serialized private LEZ claim transaction from an existing proof")]
    PrepareClaimTx {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
        #[arg(long, value_name = "PATH", help = "Distribution bundle JSON")]
        bundle: String,
        #[arg(long, value_name = "PATH", help = "Claim wallet seed file")]
        wallet: String,
        #[arg(long, value_name = "PATH", help = "Existing proof JSON path")]
        proof: Option<String>,
        #[arg(
            long = "destination-packet",
            value_name = "PATH",
            help = "Shielded destination JSON"
        )]
        destination_packet: Option<String>,
        #[arg(
            long = "claim-destination-commitment",
            value_name = "HEX",
            help = "Destination commitment hex"
        )]
        claim_destination_commitment: Option<String>,
        #[arg(
            long,
            value_name = "PATH",
            help = "Output serialized LEZ claim transaction"
        )]
        out: Option<String>,
    },
    #[command(about = "Check claimant eligibility before proving")]
    CheckEligibility {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
        #[arg(long, value_name = "PATH", help = "Distribution bundle JSON")]
        bundle: String,
        #[arg(long, value_name = "PATH", help = "Claim wallet seed file")]
        wallet: String,
        #[arg(
            long = "destination-packet",
            value_name = "PATH",
            help = "Shielded destination JSON"
        )]
        destination_packet: Option<String>,
        #[arg(
            long = "claim-destination-commitment",
            value_name = "HEX",
            help = "Destination commitment hex"
        )]
        claim_destination_commitment: Option<String>,
    },
    #[command(about = "Submit a verified proof to the claim relayer")]
    Claim {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
        #[arg(long, value_name = "PATH", help = "Proof JSON path")]
        proof: String,
        #[arg(long, value_name = "URL", help = "Relayer URL or localnet")]
        relayer: String,
        #[arg(
            long = "serialized-lez-tx",
            value_name = "PATH",
            help = "Serialized LEZ claim transaction"
        )]
        serialized_lez_tx: String,
    },
    #[command(about = "Close local state for a distribution")]
    Close {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
    },
    #[command(about = "Verify a generated proof locally")]
    Verify {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
        #[arg(long, value_name = "PATH", help = "Proof JSON path")]
        proof: String,
    },
    #[command(about = "Write an attestation for a distribution")]
    Attest {
        #[arg(long, value_name = "NAME", help = "Distribution name")]
        airdrop: String,
    },
    #[command(about = "Inspect a shielded destination packet")]
    InspectDestination {
        #[arg(long = "destination-packet", value_name = "PATH")]
        destination_packet: String,
    },
    #[command(about = "Inspect eligibility CSV totals and privacy buckets")]
    InspectCsv {
        #[arg(long, value_name = "PATH", help = "Eligibility CSV path")]
        csv: String,
    },
    #[command(about = "Pad a CSV with deterministic decoy recipients")]
    PadCsv {
        #[arg(long, value_name = "PATH", help = "Input CSV path")]
        input: String,
        #[arg(long, value_name = "PATH", help = "Output CSV path")]
        out: String,
        #[arg(long, default_value_t = 8, help = "Minimum rows per amount bucket")]
        min_per_bucket: usize,
        #[arg(long, default_value = "decoy-", help = "Decoy seed label prefix")]
        decoy_seed_label: String,
    },
    #[command(about = "Generate a DistributionX claim key seed and public account")]
    CreateWallet {
        #[arg(long, value_name = "DIR", help = "Directory to write wallet.seed")]
        out_dir: Option<String>,
    },
    #[command(about = "Derive the public key for a wallet seed")]
    WalletPubkey {
        #[arg(long, value_name = "PATH", help = "Wallet seed file")]
        wallet: String,
    },
    #[command(about = "Copy a wallet seed into the active state directory")]
    SetWallet {
        #[arg(long, value_name = "PATH", help = "Source seed file")]
        from: String,
        #[arg(long, value_name = "PATH", help = "Destination seed file")]
        to: String,
    },
    #[command(
        about = "Derive an offline token-id label (not registered with the LEZ token program)"
    )]
    TokenId {
        #[arg(long, value_name = "NAME", help = "Token metadata name")]
        name: String,
    },
    #[command(
        about = "Register a real LEZ token-program token (creates definition + supply accounts)"
    )]
    MintToken {
        #[arg(
            long,
            value_name = "NAME",
            help = "Token name recorded by the LEZ token program"
        )]
        name: String,
        #[arg(
            long,
            value_name = "AMOUNT",
            default_value_t = 1_000_000_000_000_u64,
            help = "Total supply minted to the supply account"
        )]
        total_supply: u64,
        #[arg(
            long,
            help = "Skip the LEZ token program; derive an offline-only id instead"
        )]
        offline: bool,
    },
    #[command(about = "Print the embedded Risc0 method image id")]
    MethodId,
    #[command(about = "List local distributions in the state directory")]
    ListAirdrops,
    #[command(about = "Create sample CSV, wallet, and destination files")]
    SampleFixture {
        #[arg(
            long,
            default_value = "target/distributionx-testnet",
            value_name = "DIR"
        )]
        out_dir: String,
        #[arg(
            long,
            default_value_t = 30,
            value_name = "N",
            help = "Number of deterministic claimant test keys"
        )]
        claimants: usize,
    },
}

impl Cli {
    pub fn parse_from<I, T>(itr: I) -> Self
    where
        I: IntoIterator<Item = T>,
        T: Into<std::ffi::OsString> + Clone,
    {
        <Self as Parser>::parse_from(itr)
    }
}
