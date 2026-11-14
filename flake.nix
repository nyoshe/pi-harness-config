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
        { pkgs, self', ... }:
        {
          # The Pi package as a store path, with the bundled pi-web-access in node_modules.
          # Pi's own packages (peer dependencies) are left out: Pi provides them at runtime.
          packages.default = pkgs.buildNpmPackage {
            pname = "pi-harness-config";
            inherit (builtins.fromJSON (builtins.readFile ./package.json)) version;

            src = ./.;
            npmDepsHash = "sha256-no1pZq48tpmsoAolX7KO0pLPETbj8HW9ytCbnjEZ1/M=";
            npmInstallFlags = [ "--omit=peer" ];
            dontNpmBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              cp -r package.json extensions skills system node_modules $out/
              runHook postInstall
            '';
          };

          # Sandboxed benchmark runner (bench/README.md). Runs bench/run.sh from the current
          # checkout, not the store, so uncommitted harness changes and node_modules are tested.
          packages.bench = pkgs.writeShellApplication {
            name = "bench";
            runtimeInputs = with pkgs; [
              bubblewrap
              coreutils
              gawk
              git
              gnugrep
              jq
              nodejs
              socat
            ];
            text = ''
              root=$(git rev-parse --show-toplevel 2>/dev/null) || {
                echo "bench: run from inside a pi-harness-config checkout" >&2
                exit 1
              }
              exec bash "$root/bench/run.sh" "$@"
            '';
          };
          apps.bench = {
            type = "app";
            program = "${self'.packages.bench}/bin/bench";
          };
        };

      flake.homeManagerModules.default = import ./nix/home-manager.nix { inherit inputs; };
    };
}
