{
  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    distributionx_client.url = "path:../distributionx_client_module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
      configOverrides = {
        name = "distributionx";
      };
    };
}
