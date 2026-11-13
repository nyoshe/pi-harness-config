{ inputs }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pi.harness;
in
{
  options.programs.pi.harness = {
    enable = lib.mkEnableOption "the Pi harness config package in Pi's settings.json";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "pi-harness-config.packages.\${system}.default";
      description = "The harness package. Pi loads it from this store path, pinned by the flake lock.";
    };
  };

  config = lib.mkIf cfg.enable {
    # settings.json is Pi-owned (it also holds model and thinking choices), so merge
    # instead of replacing the file. Older git: and npm: entries for this package and
    # for pi-web-access are dropped, since the store path now provides both.
    home.activation.piHarnessPackage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings="$HOME/.pi/agent/settings.json"
      run mkdir -p "$(dirname "$settings")"
      [ -s "$settings" ] || echo '{}' > "$settings"
      tmp="$(mktemp)"
      ${lib.getExe pkgs.jq} --arg pkg ${lib.escapeShellArg "${cfg.package}"} \
        '.packages = (((.packages // []) | map(select(
            (test("pi-harness-config|pi-web-access") | not)
          ))) + [$pkg])' \
        "$settings" > "$tmp" && run install -m 644 "$tmp" "$settings"
      rm -f "$tmp"
    '';
  };
}
