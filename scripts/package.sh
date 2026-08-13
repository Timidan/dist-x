#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

OUT_DIR="${DISTRIBUTIONX_LGX_DIR:-${ROOT}/target/lgx}"
VARIANT="${DISTRIBUTIONX_LGX_VARIANT:-linux-amd64-dev}"
CARGO_PROFILE="${DISTRIBUTIONX_CARGO_PROFILE:-release}"
CHECKSUM_FILE="${OUT_DIR}/SHA256SUMS"

usage() {
  cat <<'EOF'
Usage: scripts/package.sh

Builds the two unsigned development LGX assets used by the Basecamp path:
  target/lgx/distributionx-client.lgx
  target/lgx/DistributionX-ui.lgx
  target/lgx/SHA256SUMS

Environment:
  DISTRIBUTIONX_LGX_DIR          Output directory. Default: target/lgx.
  DISTRIBUTIONX_LGX_VARIANT      LGX variant name. Default: linux-amd64-dev.
  DISTRIBUTIONX_CARGO_PROFILE   debug or release. Default: release.
  LGX_BIN                       Override lgx binary path.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() {
  printf '[distributionx-lgx] %s\n' "$*"
}

find_tool() {
  local name="$1"
  if command -v "${name}" >/dev/null 2>&1; then
    command -v "${name}"
    return
  fi
  find /nix/store -maxdepth 4 -path "*/bin/${name}" 2>/dev/null | sort | tail -n 1
}

LGX_BIN="${LGX_BIN:-$(find_tool lgx)}"
if [[ -z "${LGX_BIN}" || ! -x "${LGX_BIN}" ]]; then
  echo "lgx binary not found. Build Basecamp or put lgx on PATH." >&2
  exit 2
fi

case "${CARGO_PROFILE}" in
  debug)
    cargo_args=()
    cli_path="${ROOT}/target/debug/distributionx-cli"
    ;;
  release)
    cargo_args=(--release)
    cli_path="${ROOT}/target/release/distributionx-cli"
    ;;
  *)
    echo "Unsupported DISTRIBUTIONX_CARGO_PROFILE=${CARGO_PROFILE}; use debug or release." >&2
    exit 2
    ;;
esac

mkdir -p "${OUT_DIR}"

log "Checking Risc0 toolchain"
bash scripts/risc0-setup.sh

log "Building Rust CLI (${CARGO_PROFILE})"
cargo +1.94.0 build --locked -p distributionx-cli "${cargo_args[@]}"
export DISTRIBUTIONX_CLI="${cli_path}"

log "Building distributionx_client Logos module"
(cd distributionx_client_module && nix --extra-experimental-features 'nix-command flakes' build -L)

log "Building DistributionX Basecamp UI LGX"
rm -f "${OUT_DIR}/distributionx-ui-result"
nix --extra-experimental-features 'nix-command flakes' build -L ./basecamp-app#lgx -o "${OUT_DIR}/distributionx-ui-result"
cp -f "${OUT_DIR}/distributionx-ui-result/logos-distributionx-module.lgx" "${OUT_DIR}/DistributionX-ui.lgx"
chmod u+w "${OUT_DIR}/DistributionX-ui.lgx" 2>/dev/null || true

log "Staging self-contained core module"
rm -rf "${OUT_DIR}/staged-modules"
bash scripts/prepare-modules.sh \
  "${OUT_DIR}/staged-modules" \
  distributionx_client_module/result/lib >/tmp/distributionx-lgx-stage.log

log "Packing self-contained distributionx_client LGX"
chmod u+w "${OUT_DIR}/distributionx-client.lgx" 2>/dev/null || true
python3 - "${OUT_DIR}" "${VARIANT}" <<'PY'
import gzip
import hashlib
import json
import os
import tarfile
import sys
from io import BytesIO
from pathlib import Path

out_dir = Path(sys.argv[1])
variant = sys.argv[2]
stage = out_dir / "staged-modules" / "distributionx_client"
out = out_dir / "distributionx-client.lgx"

if not stage.is_dir():
    raise SystemExit(f"staged module missing: {stage}")

files = []
for path in sorted(stage.rglob("*")):
    if path.is_file():
        rel = path.relative_to(stage).as_posix()
        files.append((rel, path, path.read_bytes()))

def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

leaf_concat = bytearray()
for rel, _path, data in files:
    leaf_concat.extend(rel.encode())
    leaf_concat.append(0)
    leaf_concat.extend(sha256_hex(data).encode())
    leaf_concat.append(10)

variant_hash = sha256_hex(bytes(leaf_concat))
variants_hash = sha256_hex(f"{variant}\0{variant_hash}\n".encode())
root_hash = sha256_hex(f"variants\0{variants_hash}\n".encode())

manifest = {
    "manifestVersion": "0.2.0",
    "name": "distributionx_client",
    "version": "0.1.0",
    "description": "Logos module wrapper for DistributionX private distribution client operations",
    "author": "DistributionX",
    "type": "core",
    "category": "tools",
    "icon": "",
    "dependencies": [],
    "hashes": {
        "root": root_hash,
        "variants": variants_hash,
        f"variants/{variant}": variant_hash,
    },
    "main": {variant: "distributionx_client_plugin.so"},
}

tar_buf = BytesIO()
with tarfile.open(fileobj=tar_buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
    def add_dir(name: str) -> None:
        info = tarfile.TarInfo(name)
        info.type = tarfile.DIRTYPE
        info.mode = 0o755
        info.mtime = 0
        info.uid = 0
        info.gid = 0
        info.uname = ""
        info.gname = ""
        tar.addfile(info)

    def add_file(name: str, data: bytes, mode: int) -> None:
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = mode
        info.mtime = 0
        info.uid = 0
        info.gid = 0
        info.uname = ""
        info.gname = ""
        tar.addfile(info, BytesIO(data))

    add_file("manifest.json", json.dumps(manifest, indent=2).encode(), 0o644)
    add_dir("variants")
    add_dir(f"variants/{variant}")
    seen_dirs = {"variants", f"variants/{variant}"}

    for rel, path, data in files:
        prefix = f"variants/{variant}"
        for part in rel.split("/")[:-1]:
            prefix = f"{prefix}/{part}"
            if prefix not in seen_dirs:
                add_dir(prefix)
                seen_dirs.add(prefix)
        mode = 0o755 if os.access(path, os.X_OK) else 0o644
        add_file(f"variants/{variant}/{rel}", data, mode)

out.parent.mkdir(parents=True, exist_ok=True)
with gzip.GzipFile(filename="", mode="wb", fileobj=out.open("wb"), mtime=0) as gz:
    gz.write(tar_buf.getvalue())
out.chmod(0o644)
print(out)
PY

log "Verifying LGX packages"
"${LGX_BIN}" verify "${OUT_DIR}/distributionx-client.lgx"
"${LGX_BIN}" verify "${OUT_DIR}/DistributionX-ui.lgx"

log "Writing and verifying deterministic SHA-256 checksums"
chmod u+w "${CHECKSUM_FILE}" 2>/dev/null || true
(
  cd "${OUT_DIR}"
  LC_ALL=C sha256sum \
    distributionx-client.lgx \
    DistributionX-ui.lgx >SHA256SUMS
  LC_ALL=C sha256sum --check SHA256SUMS
)

log "Artifacts"
ls -lh \
  "${OUT_DIR}/distributionx-client.lgx" \
  "${OUT_DIR}/DistributionX-ui.lgx" \
  "${CHECKSUM_FILE}"
