//! # spel-client-gen
//!
//! Generates typed Rust client code and C FFI wrappers from SPEL program IDL JSON.
//!
//! ## Usage
//!
//! ```rust,ignore
//! use spel_client_gen::generate_from_idl_json;
//! use std::fs;
//!
//! let idl_json = fs::read_to_string("my_program_idl.json")?;
//! let output = generate_from_idl_json(&idl_json)?;
//! fs::write("src/generated_client.rs", &output.client_code)?;
//! fs::write("src/generated_ffi.rs", &output.ffi_code)?;
//! ```

use spel_framework_core::idl::*;

mod codegen;
mod ffi_codegen;
mod util;

#[cfg(test)]
mod tests;

/// Output of code generation.
#[derive(Debug, Clone)]
pub struct CodegenOutput {
    /// Typed Rust client module source code.
    pub client_code: String,
    /// C FFI wrapper source code.
    pub ffi_code: String,
    /// C header file content.
    pub header: String,
}

/// Generate client + FFI code from an IDL JSON string.
pub fn generate_from_idl_json(json: &str) -> Result<CodegenOutput, String> {
    let idl: SpelIdl =
        serde_json::from_str(json).map_err(|e| format!("failed to parse IDL JSON: {}", e))?;
    generate_from_idl(&idl)
}

/// Generate client + FFI code from a parsed IDL.
pub fn generate_from_idl(idl: &SpelIdl) -> Result<CodegenOutput, String> {
    validate_rest_accounts(idl)?;
    let client_code = codegen::generate_client(idl)?;
    let ffi_code = ffi_codegen::generate_ffi(idl)?;
    let header = ffi_codegen::generate_header(idl)?;
    Ok(CodegenOutput {
        client_code,
        ffi_code,
        header,
    })
}

/// Whether the generic client may submit this instruction as a public LEE
/// transaction. Legacy IDLs omit `execution`, which retains the historical
/// public default; an explicit private-only mode fails closed.
pub(crate) fn instruction_supports_public_submission(instruction: &IdlInstruction) -> bool {
    instruction
        .execution
        .as_ref()
        .map_or(true, |execution| execution.public)
}

fn validate_rest_accounts(idl: &SpelIdl) -> Result<(), String> {
    for instruction in &idl.instructions {
        let rest_positions = instruction
            .accounts
            .iter()
            .enumerate()
            .filter_map(|(index, account)| account.rest.then_some(index))
            .collect::<Vec<_>>();
        if rest_positions.len() > 1 {
            return Err(format!(
                "instruction `{}` has more than one rest account",
                instruction.name
            ));
        }
        if let Some(index) = rest_positions.first() {
            if *index + 1 != instruction.accounts.len() {
                return Err(format!(
                    "instruction `{}` rest account must be the final account",
                    instruction.name
                ));
            }
        }
    }
    Ok(())
}
