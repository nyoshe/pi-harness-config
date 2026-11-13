{
  description = "Pi harness config: extensions, skills and system prompt guidance for local-model coding sessions";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
  };

  outputs =
    { flake-parts, systems, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import systems;

      perSystem =
        { pkgs, ... }:
        {
          # The Pi package as a store path, with the bundled pi-web-access in node_modules.
          # Pi's own packages (peer dependencies) are left out: Pi provides them at runtime.
          packages.default = pkgs.buildNpmPackage {
            pname = "pi-harness-config";
            inherit (builtins.fromJSON (builtins.readFile ./package.json)) version;

            src = ./.;
            npmDepsHash = "sha256-vcNew0jYMBIA3pulHooCSRRcLXixSXvRn3iko0dWRbU=";
            npmInstallFlags = [ "--omit=peer" ];
            dontNpmBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp -r package.json extensions skills system node_modules $out/
              runHook postInstall
            '';
          };
        };

      flake.homeManagerModules.default = import ./nix/home-manager.nix { inherit inputs; };
    };
}
