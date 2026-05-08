use distributionx_tree::{parse_csv, DistributionXTreeError};

#[test]
fn csv_rejects_duplicate_addresses() {
    let addr = "0101010101010101010101010101010101010101010101010101010101010101";
    let csv = format!("address,raw_amount\n{addr},100\n{addr},100\n");
    assert_eq!(
        parse_csv(&csv).unwrap_err(),
        DistributionXTreeError::CliDuplicateAddr
    );
}

#[test]
fn csv_accepts_small_bucket() {
    // The hard 8-recipient floor was lifted: parse_csv accepts any non-empty CSV.
    // Operators see the resulting bucket population via `inspect-csv` and can
    // decide whether to pad up to the documented baseline (k>=8) with `pad-csv`.
    let mut csv = String::from("address,raw_amount\n");
    for i in 0..3u8 {
        csv.push_str(&format!("{:064x},100\n", i + 1));
    }
    let parsed = parse_csv(&csv).unwrap();
    assert_eq!(parsed.rows.len(), 3);
    assert_eq!(parsed.bucket_table, vec![100]);
    assert_eq!(parsed.population_per_bucket, vec![3]);
}

#[test]
fn csv_accepts_eight_member_bucket() {
    let mut csv = String::from("address,raw_amount\n");
    for i in 0..8u8 {
        csv.push_str(&format!("{:064x},100\n", i + 1));
    }
    let parsed = parse_csv(&csv).unwrap();
    assert_eq!(parsed.rows.len(), 8);
    assert_eq!(parsed.bucket_table, vec![100]);
}
