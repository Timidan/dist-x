const BUNDLED_IDL_JSON: &str = include_str!("../idl/distributionx.json");

#[cfg(feature = "spel-idl")]
#[allow(dead_code)]
#[path = "program.rs"]
mod spel_program;

pub fn idl_json() -> &'static str {
    BUNDLED_IDL_JSON
}

#[cfg(feature = "spel-idl")]
pub fn framework_instruction_idl_json() -> &'static str {
    spel_program::PROGRAM_IDL_JSON
}

pub fn emit_idl_json() -> String {
    #[cfg(feature = "spel-idl")]
    {
        return complete_framework_idl(framework_instruction_idl_json(), idl_json())
            .unwrap_or_else(|err| {
                eprintln!(
                    "DistributionX SPEL IDL falling back to bundled IDL after framework IDL merge failed: {err}"
                );
                idl_json().to_owned()
            });
    }

    #[cfg(not(feature = "spel-idl"))]
    {
        idl_json().to_owned()
    }
}

#[cfg(feature = "spel-idl")]
fn complete_framework_idl(
    framework_idl: &str,
    bundled_idl: &str,
) -> Result<String, serde_json::Error> {
    let mut framework: serde_json::Value = serde_json::from_str(framework_idl)?;
    let bundled: serde_json::Value = serde_json::from_str(bundled_idl)?;

    for key in ["accounts", "types", "errors"] {
        copy_bundled_section_if_framework_empty(&mut framework, &bundled, key);
    }

    serde_json::to_string_pretty(&framework)
}

#[cfg(feature = "spel-idl")]
fn copy_bundled_section_if_framework_empty(
    framework: &mut serde_json::Value,
    bundled: &serde_json::Value,
    key: &str,
) {
    let Some(bundled_value) = bundled.get(key) else {
        return;
    };
    if is_empty_array(bundled_value) {
        return;
    }

    if framework.get(key).map_or(true, is_empty_array) {
        framework[key] = bundled_value.clone();
    }
}

#[cfg(feature = "spel-idl")]
fn is_empty_array(value: &serde_json::Value) -> bool {
    value.as_array().is_some_and(Vec::is_empty)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::errors::*;
    use serde_json::{json, Value};

    fn bundled_idl() -> Value {
        serde_json::from_str(idl_json()).expect("bundled IDL must be valid JSON")
    }

    fn instruction_surface(idl: &Value) -> Value {
        let instructions = idl
            .get("instructions")
            .and_then(Value::as_array)
            .expect("IDL must contain an instructions array");

        Value::Array(
            instructions
                .iter()
                .map(|instruction| {
                    let accounts = instruction
                        .get("accounts")
                        .and_then(Value::as_array)
                        .expect("instruction must contain accounts")
                        .iter()
                        .map(|account| {
                            let mut surface = serde_json::Map::new();
                            for key in ["name", "writable", "signer", "init", "pda"] {
                                if let Some(value) = account.get(key) {
                                    surface.insert(key.to_string(), value.clone());
                                }
                            }
                            Value::Object(surface)
                        })
                        .collect::<Vec<_>>();

                    let args = instruction
                        .get("args")
                        .and_then(Value::as_array)
                        .expect("instruction must contain args")
                        .iter()
                        .map(|arg| {
                            json!({
                                "name": arg.get("name").expect("arg must have a name"),
                                "type": arg.get("type").expect("arg must have a type"),
                            })
                        })
                        .collect::<Vec<_>>();

                    json!({
                        "name": instruction.get("name").expect("instruction must have a name"),
                        "accounts": accounts,
                        "args": args,
                    })
                })
                .collect(),
        )
    }

    #[test]
    fn bundled_idl_declares_expected_instruction_surface() {
        let idl = bundled_idl();

        assert_eq!(
            instruction_surface(&idl),
            json!([
                {
                    "name": "init_airdrop",
                    "accounts": [
                        {
                            "name": "airdrop",
                            "writable": true,
                            "signer": false,
                            "init": true,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "airdrop"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "vault",
                            "writable": true,
                            "signer": false,
                            "init": true,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "vault"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "distributor",
                            "writable": false,
                            "signer": true,
                            "init": false
                        }
                    ],
                    "args": [
                        {"name": "airdrop_id", "type": {"array": ["u8", 32]}},
                        {"name": "token_id", "type": {"array": ["u8", 32]}},
                        {"name": "merkle_root", "type": {"array": ["u8", 32]}},
                        {"name": "tree_depth", "type": "u8"},
                        {"name": "bucket_table_hash", "type": {"array": ["u8", 32]}},
                        {"name": "bucket_table", "type": {"vec": "u64"}},
                        {"name": "image_id", "type": {"array": ["u8", 32]}},
                        {"name": "expiry_unix", "type": "i64"},
                        {"name": "recovery_address", "type": {"array": ["u8", 32]}},
                        {"name": "now_unix", "type": "i64"}
                    ]
                },
                {
                    "name": "fund",
                    "accounts": [
                        {
                            "name": "airdrop",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "airdrop"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "vault",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "vault"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "distributor",
                            "writable": false,
                            "signer": true,
                            "init": false
                        }
                    ],
                    "args": [
                        {"name": "airdrop_id", "type": {"array": ["u8", 32]}},
                        {"name": "amount", "type": "u64"},
                        {"name": "now_unix", "type": "i64"}
                    ]
                },
                {
                    "name": "claim",
                    "accounts": [
                        {
                            "name": "airdrop",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "airdrop"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "nullifier_record",
                            "writable": true,
                            "signer": false,
                            "init": true,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "nullifier"},
                                    {"kind": "arg", "path": "airdrop_id"},
                                    {"kind": "arg", "path": "nullifier"}
                                ]
                            }
                        },
                        {
                            "name": "vault",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "vault"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        }
                    ],
                    "args": [
                        {"name": "airdrop_id", "type": {"array": ["u8", 32]}},
                        {"name": "nullifier", "type": {"array": ["u8", 32]}},
                        {"name": "receipt_bytes", "type": {"vec": "u8"}},
                        {"name": "now_unix", "type": "i64"}
                    ]
                },
                {
                    "name": "claim_private",
                    "accounts": [
                        {
                            "name": "airdrop",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "airdrop"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "nullifier_record",
                            "writable": true,
                            "signer": false,
                            "init": true,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "nullifier"},
                                    {"kind": "arg", "path": "airdrop_id"},
                                    {"kind": "arg", "path": "nullifier"}
                                ]
                            }
                        },
                        {
                            "name": "vault",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "vault"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        }
                    ],
                    "args": [
                        {"name": "airdrop_id", "type": {"array": ["u8", 32]}},
                        {"name": "bucket_id", "type": "u8"},
                        {"name": "nullifier", "type": {"array": ["u8", 32]}},
                        {"name": "claim_destination_commitment", "type": {"array": ["u8", 32]}},
                        {"name": "claimant_address", "type": {"array": ["u8", 32]}},
                        {"name": "salt", "type": {"array": ["u8", 32]}},
                        {"name": "claim_sig", "type": {"vec": "u8"}},
                        {"name": "merkle_siblings", "type": {"vec": {"array": ["u8", 32]}}},
                        {"name": "merkle_path_is_right", "type": {"vec": "bool"}},
                        {"name": "now_unix", "type": "i64"}
                    ]
                },
                {
                    "name": "close",
                    "accounts": [
                        {
                            "name": "airdrop",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "airdrop"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "vault",
                            "writable": true,
                            "signer": false,
                            "init": false,
                            "pda": {
                                "seeds": [
                                    {"kind": "const", "value": "vault"},
                                    {"kind": "arg", "path": "airdrop_id"}
                                ]
                            }
                        },
                        {
                            "name": "recovery",
                            "writable": true,
                            "signer": false,
                            "init": false
                        },
                        {
                            "name": "distributor",
                            "writable": false,
                            "signer": true,
                            "init": false
                        }
                    ],
                    "args": [
                        {"name": "airdrop_id", "type": {"array": ["u8", 32]}}
                    ]
                }
            ])
        );
    }

    #[test]
    fn bundled_idl_declares_all_program_error_codes() {
        let idl = bundled_idl();
        let errors = idl
            .get("errors")
            .and_then(Value::as_array)
            .expect("IDL must contain an errors array")
            .iter()
            .map(|error| {
                let code = error
                    .get("code")
                    .and_then(Value::as_u64)
                    .expect("error must have a numeric code") as u32;
                let name = error
                    .get("name")
                    .and_then(Value::as_str)
                    .expect("error must have a name");
                let message = error
                    .get("message")
                    .and_then(Value::as_str)
                    .expect("error must have a message");
                assert!(!message.is_empty(), "error {name} must have a message");
                (code, name.to_owned())
            })
            .collect::<Vec<_>>();

        assert_eq!(
            errors,
            vec![
                (E_AIRDROP_CLOSED, "E_AIRDROP_CLOSED".to_string()),
                (E_AIRDROP_ID_MISMATCH, "E_AIRDROP_ID_MISMATCH".to_string()),
                (E_ROOT_MISMATCH, "E_ROOT_MISMATCH".to_string()),
                (E_BUCKET_OUT_OF_RANGE, "E_BUCKET_OUT_OF_RANGE".to_string()),
                (E_BAD_PROOF, "E_BAD_PROOF".to_string()),
                (E_ALREADY_CLAIMED, "E_ALREADY_CLAIMED".to_string()),
                (E_VAULT_INSUFFICIENT, "E_VAULT_INSUFFICIENT".to_string()),
                (E_TRANSFER_FAILED, "E_TRANSFER_FAILED".to_string()),
                (E_DISTRIBUTOR_ONLY, "E_DISTRIBUTOR_ONLY".to_string()),
                (E_TREE_DEPTH_INVALID, "E_TREE_DEPTH_INVALID".to_string()),
                (E_BUCKET_TABLE_INVALID, "E_BUCKET_TABLE_INVALID".to_string()),
                (E_BUCKET_AMOUNT_ZERO, "E_BUCKET_AMOUNT_ZERO".to_string()),
                (E_IMAGE_ID_MISMATCH, "E_IMAGE_ID_MISMATCH".to_string()),
                (
                    E_BAD_DESTINATION_COMMITMENT,
                    "E_BAD_DESTINATION_COMMITMENT".to_string(),
                ),
                (E_OVERFLOW, "E_OVERFLOW".to_string()),
                (E_EXPIRY_INVALID, "E_EXPIRY_INVALID".to_string()),
                (E_NULLIFIER_MISMATCH, "E_NULLIFIER_MISMATCH".to_string()),
            ]
        );
    }

    #[cfg(feature = "spel-idl")]
    #[test]
    fn bundled_instruction_surface_matches_framework_idl() {
        let bundled = bundled_idl();
        let framework: Value = serde_json::from_str(framework_instruction_idl_json())
            .expect("framework IDL must be valid JSON");

        assert_eq!(bundled["name"], framework["name"]);
        assert_eq!(bundled["version"], framework["version"]);
        assert_eq!(
            instruction_surface(&bundled),
            instruction_surface(&framework)
        );
    }
}
