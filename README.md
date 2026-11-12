# pi-harness-config

Personal [Pi](https://pi.dev) package: extensions and skills for the local-LLM coding harness.

## Contents

| Path | Provides |
|---|---|
| `extensions/nix.ts` | Tools `nix_eval`, `nix_build`, `nix_flake_check`, `nix_search` |
| `skills/nix/SKILL.md` | Nix/NixOS/Home Manager workflow guidance |
| `skills/screenshot/SKILL.md` | Capture the focused screen/window with niri and view it |
| `skills/nix-search/SKILL.md` | Look up packages, providers of a command, and options without guessing |

## Install

```sh
pi install git:github.com/nyoshe/pi-harness-config
```

On NixOS this is declared by the `local_LLM` bundle in the nixos config, which adds the source
to `~/.pi/agent/settings.json`.

## Adding things

Drop a TypeScript extension in `extensions/`, a skill directory (with `SKILL.md`) in `skills/`,
or Markdown prompt templates in `prompts/`. Pi discovers them by convention.

## Guards and helpers

| Path | Provides |
|---|---|
| `extensions/permission-gate.ts` | Asks before dangerous bash (rm -rf, sudo, force push, `nixos-rebuild switch`, GC); blocks when headless |
| `extensions/protected-paths.ts` | Blocks write/edit on secrets, `.git/`, `flake.lock`, `hardware-configuration.nix` (bash is not covered) |
| `extensions/todo.ts` | `todo` tool and `/todos` command: a task list the model keeps |
| `extensions/question.ts` | `question` tool: lets the model ask you instead of guessing |
| `extensions/git-checkpoint.ts` | Git stash checkpoint each turn so `/fork` can restore code |
| `extensions/edit-guard.ts` | Blocks `write` over existing files longer than 40 lines so the model uses `edit` |

`todo`, `question` and `git-checkpoint` are copied unchanged from Pi's bundled examples;
`permission-gate` and `protected-paths` are adapted from them.

Pi's built-in compaction already summarizes with the active model. The bundled
`custom-compaction.ts` example is hard-wired to Gemini Flash, so it is not included.
