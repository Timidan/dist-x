pub mod airdrop;
#[cfg(feature = "host")]
pub mod bundle;
pub mod csv;
pub mod errors;
pub mod hash;
pub mod leaf;
pub mod merkle;

pub use errors::DistributionXTreeError;
pub use hash::{h_empty, h_leaf, h_node, h_null};
// Re-exports added in subsequent tasks:
pub use airdrop::{airdrop_id, bucket_table_hash}; // Task 3
#[cfg(feature = "host")]
pub use bundle::{build_bundle, build_bundle_with_airdrop_id, BundleV1};
pub use csv::{parse_csv, BucketProposal, CsvRow}; // Task 5
pub use leaf::{leaf_hash, LeafInput}; // Task 4, Task 7
pub use merkle::{MerklePath, MerkleTree}; // Task 4 // Task 6
