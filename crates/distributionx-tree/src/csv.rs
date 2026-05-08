use crate::errors::DistributionXTreeError;
use std::collections::{BTreeMap, HashSet};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CsvRow {
    pub address: [u8; 32],
    pub raw_amount: u64,
    pub bucket_id: u8,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BucketProposal {
    pub rows: Vec<CsvRow>,
    pub bucket_table: Vec<u64>,
    pub population_per_bucket: Vec<usize>,
}

pub fn parse_csv(input: &str) -> Result<BucketProposal, DistributionXTreeError> {
    let mut lines = input.lines();
    if lines.next() != Some("address,raw_amount") {
        return Err(DistributionXTreeError::CliAddrNonCanonical);
    }

    let mut raw = Vec::new();
    let mut seen = HashSet::new();
    for line in lines {
        let (addr_s, amount_s) = line
            .split_once(',')
            .ok_or(DistributionXTreeError::CliAddrNonCanonical)?;
        let address = parse_hex_32(addr_s).ok_or(DistributionXTreeError::CliAddrNonCanonical)?;
        if !seen.insert(address) {
            return Err(DistributionXTreeError::CliDuplicateAddr);
        }
        let raw_amount = amount_s
            .parse::<u64>()
            .map_err(|_| DistributionXTreeError::CliBucketOob)?;
        raw.push((address, raw_amount));
    }

    if raw.len() > 50_000 {
        return Err(DistributionXTreeError::CliPopulationCap);
    }

    let mut amount_counts = BTreeMap::<u64, usize>::new();
    for (_, amount) in &raw {
        *amount_counts.entry(*amount).or_default() += 1;
    }

    if amount_counts.len() > 32 {
        return Err(DistributionXTreeError::CliBucketOob);
    }
    // The bounty's documented privacy property (observer-unlinkability among same-bucket
    // recipients) holds with anonymity-set probability 1/k per bucket. We do not block
    // small buckets here; callers (e.g. `inspect-csv`) surface a warning when k < 8 so
    // operators can decide whether to pad with `pad-csv` for the recommended baseline.

    let bucket_table: Vec<u64> = amount_counts.keys().copied().collect();
    let population_per_bucket: Vec<usize> = bucket_table
        .iter()
        .map(|amount| amount_counts[amount])
        .collect();
    let rows = raw
        .into_iter()
        .map(|(address, raw_amount)| CsvRow {
            address,
            raw_amount,
            bucket_id: bucket_table.iter().position(|v| *v == raw_amount).unwrap() as u8,
        })
        .collect();

    Ok(BucketProposal {
        rows,
        bucket_table,
        population_per_bucket,
    })
}

fn parse_hex_32(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }

    let mut out = [0u8; 32];
    for i in 0..32 {
        out[i] = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}
