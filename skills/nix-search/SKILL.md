---
name: nix-search
description: Find the right Nix package or NixOS/Home Manager option. Use when you need a package attribute name, which package provides a command or file, a package's version/license/platforms, or whether an option exists. Never guess names.
---

# Finding Nix packages and options

A guessed attribute name that is wrong costs a failed build. Look it up, then confirm it evaluates.

## Packages

1. Search with the `nix_search` tool (or `nix search nixpkgs <terms> --json`).
   - Terms are regexes and are ANDed. Anchor an exact name: `'^ripgrep$'`.
   - Search by what it does ("pdf viewer"), not only by name.
   - Results like `nixpkgs#foo` mean attribute `pkgs.foo`. Nested sets (`python3Packages.requests`, `kdePackages.dolphin`, `nodePackages.x`) must be written in full.
2. Confirm and inspect the candidate with `nix_eval`:
   - `nixpkgs#<attr>.meta.description`
   - `nixpkgs#<attr>.version`
   - `nixpkgs#<attr>.meta.license.spdxId`
   - `nixpkgs#<attr>.meta.platforms` (is `x86_64-linux` in it?)
   - `nixpkgs#<attr>.meta.broken` / `.meta.insecure` (must be false)
   - `nixpkgs#<attr>.meta.mainProgram` (the command it installs)
3. In a flake in this repo, prefer the repo's own pin over the registry: use `.#nixosConfigurations.<host>.pkgs.<attr>` so the version matches what the system builds.

## Which package provides a command or file

- Try `nix_search` with the command name first; `mainProgram` often matches the attribute.
- If `nix-locate` has an index (`ls ~/.cache/nix-index`), use `nix-locate --minimal --whole-name --at-root /bin/<cmd>`. If the index is missing, do not build it on your own (it downloads a lot); say so and fall back to the next option.
- Otherwise search https://search.nixos.org/packages (use the web tools if available) with the `programs:` filter.
- Do not guess that the command name equals the package name (`rg` is `ripgrep`, `convert` is `imagemagick`).

## Options

- NixOS option: `nix_eval` on `.#nixosConfigurations.<host>.options.<path>.description` (and `.type.description`, `.default`) returns the real definition for this system. List what exists under a prefix with `builtins.attrNames`.
- Home Manager option: the same on `.#homeConfigurations."<user>@<host>".options.<path>`.
- Repo-defined options (for example `bundles.*`): `grep -rn "mkOption\|mkEnableOption" <modules dir>` and read the module.
- If an option path does not exist, you made it up. Search by a keyword instead (`grep -rn <keyword>` in nixpkgs/HM module sources, or search.nixos.org/options and home-manager-options docs via the web tools).

## Trying a package without installing it

- `nix run nixpkgs#<attr> -- <args>` or `nix shell nixpkgs#<attr> -c <cmd>` runs it from the store without changing the system. This downloads the package; fine for a one-off check, but do not add it to the user's config unless asked.

## Rules

- Always report the exact attribute and version you found, and say if you could not verify it.
- Prefer a package already in the repo's inputs over adding a new flake input.
- Unfree packages need `allowUnfree`; say so instead of enabling it silently.
- Adding the package to the user's config is a separate step: follow the `nix` skill (edit, `nix_eval`/`nix_build` dry run, ask the user to switch).
