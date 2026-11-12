---
name: nix-search
description: Find the right Nix package or NixOS/Home Manager option with `nh search`. Use when you need a package attribute name, which package provides a command, a package's version, or whether an option exists. Never guess names.
---

# Finding Nix packages and options with `nh search`

`nh search` queries search.nixos.org (packages, options, programs, nixpkgs PRs/issues). A guessed attribute name that is wrong costs a failed build, so look it up, then confirm it evaluates.

Always pass `-j` and filter with `jq`: the default output is colored, has terminal hyperlinks and is long. Keep `-l` small (5-10). It needs network; the channel defaults to `nixos-unstable`, so use `-c <channel>` if this system pins another.

## Packages

```bash
nh search packages -j -l 8 "<terms>" 2>/dev/null \
  | jq -r '.results[] | "\(.package_attr_set)/\(.package_attr_name)  \(.package_pversion)  main=\(.package_mainProgram // "-")  \(.package_description)"'
```

- Search by what it does ("pdf viewer"), not only by name.
- `package_attr_set` is `No package set` for top-level packages (`pkgs.<attr>`). Otherwise write the full path, for example `python3Packages.requests` or `kdePackages.dolphin`.
- Useful fields: `package_pversion`, `package_mainProgram`, `package_license_set`, `package_homepage`, `package_programs` (every binary it installs).

## Which package provides a command

Search for the command name and keep only results whose `package_programs` contain it:

```bash
nh search packages -j -l 15 "<command>" 2>/dev/null \
  | jq -r '.results[] | select((.package_programs // []) | index("<command>")) | "\(.package_attr_name)  \(.package_pversion)"'
```

Do not assume the command equals the package name (`rg` is `ripgrep`, `dig` is `bind`/`dig`, `convert` is `imagemagick`). If several packages match, prefer the one whose name equals `package_mainProgram` or the plain upstream name, and say which alternatives exist.

## Options

```bash
nh search options -j -l 5 "services.llama-cpp.enable" 2>/dev/null \
  | jq -r '.results[] | "\(.option_name) :: \(.option_type)  default=\(.option_default)\n\(.option_description)"'
```

- Searches NixOS options. Home Manager options are included too; check the `option_flake` / `flake_name` fields to tell them apart.
- For what this system actually defines (including repo options like `bundles.*`), `nix_eval` `.#nixosConfigurations.<host>.options.<path>.description`, or `grep -rn "mkOption\|mkEnableOption" <modules dir>`.
- If the option path does not exist, you made it up: search by keyword instead.

## Pull requests and issues

`nh search prs "<terms>"` and `nh search issues "<terms>"` find nixpkgs PRs (with branch reachability) and issues. Use them when a package is missing, broken or outdated, to see whether a fix exists and has reached the channel. Keep `-l` small.

## Confirm it works on this system

After choosing a candidate, check it against this repo's own pin rather than the online channel, with `nix_eval`:

- `.#nixosConfigurations.<host>.pkgs.<attr>.version`
- `.#nixosConfigurations.<host>.pkgs.<attr>.meta.broken` and `.meta.insecure` (must be false)
- `.#nixosConfigurations.<host>.pkgs.<attr>.meta.platforms` (contains `x86_64-linux`)

The repo's nixpkgs may be older or newer than `nixos-unstable`, so a package found online may be missing locally or at another version. If so, say so.

## Fallbacks

- No network or `nh` fails: use the `nix_search` tool (`nix search nixpkgs '^name$' --json`, terms are regexes, ANDed).
- Try without installing: `nix run nixpkgs#<attr> -- <args>` or `nix shell nixpkgs#<attr> -c <cmd>`. It downloads the package; fine for a one-off check, but do not add it to the user's config unless asked.

## Rules

- Report the exact attribute and version you found, and say if you could not verify it locally.
- Prefer a package already in the repo's inputs over adding a new flake input.
- Unfree packages need `allowUnfree`; say so instead of enabling it silently.
- Adding the package to the user's config is a separate step: follow the `nix` skill (edit, `nix_eval`/`nix_build` dry run, ask the user to switch).
- `nh` can also switch systems (`nh os switch`, `nh home switch`, `nh clean`). Never run those; only `nh search`.
