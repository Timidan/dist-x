#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DistributionXTreeError {
    #[error("CLI_ADDR_NON_CANONICAL")]
    CliAddrNonCanonical,
    #[error("CLI_DUPLICATE_ADDR")]
    CliDuplicateAddr,
    #[error("CLI_ANONYMITY_FLOOR")]
    CliAnonymityFloor,
    #[error("CLI_POPULATION_CAP")]
    CliPopulationCap,
    #[error("CLI_BUCKET_OOB")]
    CliBucketOob,
    #[error("CLI_UNDERFUNDED")]
    CliUnderfunded,
    #[error("CLI_SALT_DUPLICATE")]
    CliSaltDuplicate,
    #[error("CLI_SALT_CSPRNG_FAIL")]
    CliSaltCsprngFail,
}
