use std::{
    env, fs,
    path::{Path, PathBuf},
    process::Command,
};

const BUNDLED_IDL_PATH: &str = "idl/distributionx.json";
const PROGRAM_SOURCE_PATH: &str = "src/program.rs";
const EMIT_FRAMEWORK_IDL_ARG: &str = "--distributionx-emit-framework-idl";

#[allow(dead_code)]
mod framework_idl_emitter {
    spel_framework::generate_idl!("src/program.rs");

    pub fn emit_to_stdout() {
        main();
    }
}

fn main() {
    if env::args().any(|arg| arg == EMIT_FRAMEWORK_IDL_ARG) {
        framework_idl_emitter::emit_to_stdout();
        return;
    }

    println!("cargo:rerun-if-changed={BUNDLED_IDL_PATH}");
    println!("cargo:rerun-if-changed={PROGRAM_SOURCE_PATH}");

    if env::var_os("CARGO_FEATURE_SPEL_IDL").is_none() {
        return;
    }

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR must be set by Cargo"));
    let out_path = out_dir.join("distributionx.json");

    match emit_framework_idl(&out_path) {
        Ok(()) => {
            println!(
                "cargo:warning=DistributionX SPEL IDL emitted from spel-framework generator: {}",
                out_path.display()
            );
        }
        Err(err) => {
            println!(
                "cargo:warning=DistributionX SPEL IDL falling back to bundled IDL after spel-framework emission failed: {err}"
            );
            emit_bundled_idl(&out_path);
            println!(
                "cargo:warning=DistributionX SPEL IDL emitted from bundled fallback: {}",
                out_path.display()
            );
        }
    }
}

fn emit_framework_idl(out_path: &Path) -> Result<(), String> {
    let framework_idl = run_framework_idl_emitter()?;
    let bundled_idl = fs::read_to_string(BUNDLED_IDL_PATH)
        .map_err(|err| format!("failed to read bundled DistributionX IDL: {err}"))?;
    let completed_idl = complete_framework_idl(&framework_idl, &bundled_idl)?;

    fs::write(out_path, completed_idl)
        .map_err(|err| format!("failed to write framework DistributionX IDL: {err}"))
}

fn run_framework_idl_emitter() -> Result<String, String> {
    let current_exe =
        env::current_exe().map_err(|err| format!("failed to locate build script binary: {err}"))?;
    let output = Command::new(current_exe)
        .arg(EMIT_FRAMEWORK_IDL_ARG)
        .output()
        .map_err(|err| format!("failed to run framework IDL emitter: {err}"))?;

    if !output.status.success() {
        return Err(format!(
            "framework IDL emitter exited with status {}: {}",
            output.status,
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    String::from_utf8(output.stdout)
        .map_err(|err| format!("framework IDL emitter produced non-UTF-8 output: {err}"))
        .and_then(|json| {
            if json.trim().is_empty() {
                Err("framework IDL emitter produced empty output".to_string())
            } else {
                Ok(json)
            }
        })
}

fn complete_framework_idl(framework_idl: &str, bundled_idl: &str) -> Result<String, String> {
    let mut framework: serde_json::Value = serde_json::from_str(framework_idl.trim())
        .map_err(|err| format!("framework IDL JSON is invalid: {err}"))?;
    let bundled: serde_json::Value = serde_json::from_str(bundled_idl)
        .map_err(|err| format!("bundled IDL JSON is invalid: {err}"))?;

    for key in ["accounts", "types", "errors"] {
        copy_bundled_section_if_framework_empty(&mut framework, &bundled, key);
    }

    serde_json::to_string_pretty(&framework)
        .map_err(|err| format!("failed to serialize framework IDL JSON: {err}"))
}

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

    let framework_empty = framework.get(key).is_none_or(is_empty_array);
    if framework_empty {
        framework[key] = bundled_value.clone();
        if key == "errors" {
            println!(
                "cargo:warning=DistributionX SPEL IDL preserved bundled errors because lez-framework emitted no error metadata"
            );
        }
    }
}

fn is_empty_array(value: &serde_json::Value) -> bool {
    value.as_array().is_some_and(Vec::is_empty)
}

fn emit_bundled_idl(out_path: &Path) {
    let idl =
        fs::read_to_string(BUNDLED_IDL_PATH).expect("failed to read bundled DistributionX IDL");
    fs::write(out_path, idl).expect("failed to emit bundled DistributionX IDL");
}
