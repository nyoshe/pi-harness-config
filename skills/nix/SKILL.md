---
name: nix
description: Work on Nix, NixOS and Home Manager code. Use when editing .nix files, flakes, modules or when a build/eval fails.
---

# Nix workflow

Tools: `nix_eval`, `nix_build`, `nix_flake_check`, `nix_search` (plus `bash` for anything else).

## Before editing
- Read the surrounding module and match its style: how options are declared, how `lib` is imported, attribute ordering.
- Find existing options with `grep -rn "<optionName>"` before inventing new ones.
- New files must be `git add`ed (`git add -N <file>` is enough) or flakes will not see them.

## Verify after editing
1. `nix_eval` the specific attribute you changed. It is fast and shows the real value.
2. `nix_build` with `dry_run` first, then a real build only if needed.
3. Run the repo's formatter and linters if present (`nix fmt`, `statix check`, `deadnix`).
4. Report what you ran and the real result.

## Debugging failures
- Read the **last** lines of the error, not the first. Nix prints the cause at the end.
- "attribute missing": `nix_eval` the parent attribute and list its names with `expr = "builtins.attrNames (...)"`.
- "infinite recursion": look for a module reading `config.x` inside the definition of `x`.
- Never guess a package name: use `nix_search`.

## Rules
- Do not run `nixos-rebuild switch`, `home-manager switch` or anything needing sudo. Ask the user to run it.
- Do not run `nix-collect-garbage`, `nix store delete` or edit `flake.lock` unless asked.
- Prefer `lib.mkIf`, `lib.mkMerge` and `lib.mkDefault` over duplicating attribute keys.
