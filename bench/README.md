# Bench

Runs coding tasks against harness configs, unattended, each trial in its own
[bubblewrap](https://github.com/containers/bubblewrap) sandbox, and reports pass rate,
turns, tokens, tool errors and wall time per config.

```sh
npm ci                                   # bundled extensions are loaded from node_modules
nix run .#bench -- -c baseline -c full -k 3
nix run .#bench -- -t 'nix-*' -c full -c full-no-append -k 5 -o bench/results/append-ablation
nix run .#bench -- --shell nix-python-missing   # poke around inside a task's sandbox
```

`bench/run.sh` works directly too when `bwrap`, `socat`, `node`, `jq`, `nix` and `pi` are on
`PATH`. Pi and Nix always come from the host, so the Pi version under test is the one you use.
Results land in `bench/results/<timestamp>/`: `results.jsonl` (one line per trial),
`report.txt`, and `trials/<config>/<task>/run<N>/` with the JSON event stream, Pi session,
proxy log, verify log and final workspace.

Before running, the model must already be loaded on the llama.cpp router. The runner refuses
to start otherwise, because asking for an unloaded model would make the shared router swap
models. Override with `--allow-load`. The model defaults to `defaultModel` in
`~/.pi/agent/settings.json` and must appear in `~/.pi/agent/models-store.json` (select it once
with `/model` in interactive Pi).

## Sandbox

Each trial gets a fresh workspace (a git repo of the task's `files/`) at `/work` and a fresh
`$HOME` with its own Pi agent dir, so your settings, credentials, sessions and packages are
never visible.

| Resource | Inside the sandbox |
|---|---|
| Network | None (own network namespace). The only way out is the model proxy |
| Model | `127.0.0.1:8080`, bridged to `model-proxy.mjs` on the host, which forwards model listing and inference requests that name the benchmark model. Router load/unload, other endpoints and requests for any other model get 403 and are logged in `proxy.log` |
| Files | `/work` and `$HOME` (both per trial); read-only `/nix` and `/harness`, which holds only `package.json`, `extensions`, `skills`, `system`, `prompts` and `node_modules` (never `bench/` or `.git`, so tasks, hidden tests and earlier results stay out of reach). No host home, `/run`, `/etc` beyond Nix config, D-Bus, Wayland or X11. Disk writes are not capped |
| Nix | `nix shell nixpkgs#<pkg>` works offline for anything already in the host store, using the host's pinned registry. The daemon socket is hidden: you are a trusted Nix user, so daemon access would be root-equivalent. `nix-shell -p` and `nix develop` cannot work (they need store writes) |
| Processes | Own PID namespace, killed with the sandbox; `systemd-run --user` caps memory (`--memory`, default 16G) and tasks |
| Time | Per-task timeout from `task.json`, then SIGKILL |

Verification runs in a second, fresh sandbox after the agent exits. The `verify/` directory is
copied in only then, so the agent never sees the hidden tests.

## Configs

`configs/<name>.sh` is sourced by the runner and sets `PI_ARGS` (Pi flags, with paths under
`/harness`) and optionally `HARNESS` (the checkout mounted at `/harness`, default this one).

| Config | What it loads |
|---|---|
| `baseline` | Stock Pi (built-in extensions only) |
| `full` | This harness, minus `permission-gate` (blocks everything headless; the sandbox is the guard), `pi-web-access` (no network, and it would leak answers) and `pi-open-tui` (TUI only) |
| `full-no-append` | `full` without `system/append.md` |
| `main` | `full`, loaded from the `main` checkout at `../pi-harness-config`, to A/B a branch against it |

Add a config for each change you want to measure. Configs run interleaved within each task and
run, so drift on the shared server hits all of them alike.

## Tasks

```
tasks/<name>/
  task.json        {"instruction": "...", "timeout": 900, "packages": [], "prewarm": [], "verify_packages": [], "tags": []}
  instruction.md   optional, overrides "instruction"
  files/           initial workspace, committed as the first commit
  verify/verify.sh run with cwd /work after the agent exits; exit 0 = pass. $BENCH_BASE_SHA is
                   the initial commit (compare to it, not HEAD: the agent may commit)
```

- `packages`: nixpkgs attributes on the agent's `PATH` (and verify's).
- `prewarm`: realised in the host store but not on `PATH`, so the agent has to reach them with
  `nix shell`. This is how NixOS-specific behaviour is tested (see `nix-python-missing`).
- `verify_packages`: on verify's `PATH` only.

The base `PATH` has bash, coreutils, findutils, grep, sed, awk, diffutils, patch, git, ripgrep,
fd, jq, which, procps, tar, gzip, file and nix.

Write verify scripts that cannot be satisfied by editing the tests or inputs: keep the real
checks in `verify/`, and use `git diff --quiet "$BENCH_BASE_SHA" -- <file>` to require that files stay
unchanged.

## Reading results

Harness changes are small effects. A single run on a few dozen tasks has a noise floor of
several points, so use `-k 3` or more and compare per task (the pass matrix), not just the
headline rate. `status` separates `timeout` and `error` (no model reply: infrastructure, not
the harness) from real failures. Watch turns, tokens and tool errors too; with a local model
and limited context they often move before the pass rate does.
