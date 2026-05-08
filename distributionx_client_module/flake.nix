{
  description = "DistributionX Logos Client Module";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      preConfigure = ''
        logos-cpp-generator --from-header src/distributionx_client_impl.h \
          --backend qt \
          --impl-class DistributionxClientImpl \
          --impl-header distributionx_client_impl.h \
          --metadata metadata.json \
          --output-dir ./generated_code
      '';
      postInstall = ''
        printf '%s\n' \
          '#!/usr/bin/env bash' \
          'set -euo pipefail' \
          'if [ -n "''${DISTRIBUTIONX_CLI:-}" ]; then' \
          '  exec "''${DISTRIBUTIONX_CLI}" "$@"' \
          'fi' \
          'resolved="$(command -v distributionx-cli || true)"' \
          'if [ -n "''${resolved}" ] && [ "$(readlink -f "''${resolved}")" != "$(readlink -f "$0")" ]; then' \
          '  exec "''${resolved}" "$@"' \
          'fi' \
          'echo "{\"status\":\"DISTRIBUTIONX_CLIENT_ERROR\",\"error\":\"DISTRIBUTIONX_CLI must point to the distributionx-cli binary\"}"' \
          'exit 127' \
          > "$out/lib/distributionx-cli"
        chmod +x "$out/lib/distributionx-cli"

        mkdir -p "$out/lib/distributionx_client"
        ln -s ../distributionx_client_plugin.so "$out/lib/distributionx_client/distributionx_client_plugin.so"
        ln -s ../distributionx-cli "$out/lib/distributionx_client/distributionx-cli"
        cat > "$out/lib/distributionx_client/manifest.json" <<'JSON'
        {
          "manifestVersion": "0.2.0",
          "name": "distributionx_client",
          "version": "0.1.0",
          "description": "Logos module wrapper for DistributionX private distribution client operations",
          "author": "DistributionX",
          "type": "core",
          "category": "tools",
          "dependencies": [],
          "main": "distributionx_client_plugin.so"
        }
        JSON
      '';
    };
}
