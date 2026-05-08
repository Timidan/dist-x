pub const IDL_JSON: &str = include_str!("../generated/distributionx.json");

pub fn instruction_names() -> Vec<String> {
    let value: serde_json::Value =
        serde_json::from_str(IDL_JSON).expect("valid distributionx IDL JSON");
    value["instructions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|item| item["name"].as_str().unwrap().to_owned())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::IDL_JSON;

    const CANONICAL_IDL_JSON: &str =
        include_str!("../../distributionx-program/idl/distributionx.json");
    const ROOT_IDL_JSON: &str = include_str!("../../../idl/distributionx.json");

    fn parse(value: &str) -> serde_json::Value {
        serde_json::from_str(value).expect("valid distributionx IDL JSON")
    }

    #[test]
    fn exported_idls_match_canonical_program_idl() {
        let canonical = parse(CANONICAL_IDL_JSON);
        assert_eq!(parse(IDL_JSON), canonical);
        assert_eq!(parse(ROOT_IDL_JSON), canonical);
    }

    #[test]
    fn exposes_expected_instruction_names() {
        assert_eq!(
            crate::instruction_names(),
            ["init_airdrop", "fund", "claim", "claim_private", "close"]
        );
    }
}
