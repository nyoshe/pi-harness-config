# pi-harness-config

Personal [Pi](https://pi.dev) package: extensions and skills for the local-LLM coding harness.

## Contents

| Path | Provides |
|---|---|
| `extensions/nix.ts` | Tools `nix_eval`, `nix_build`, `nix_flake_check`, `nix_search` |
| `skills/nix/SKILL.md` | Nix/NixOS/Home Manager workflow guidance |

## Install

```sh
pi install git:github.com/nyoshe/pi-harness-config
```

On NixOS this is declared by the `local_LLM` bundle in the nixos config, which adds the source
to `~/.pi/agent/settings.json`.

## Adding things

Drop a TypeScript extension in `extensions/`, a skill directory (with `SKILL.md`) in `skills/`,
or Markdown prompt templates in `prompts/`. Pi discovers them by convention.
