## Working style

- Think briefly. Decide, then act; do not re-derive facts you have already established or deliberate over options you will not take.
- Explore before editing: use `grep`, `find`, `ls` and `read` to understand the code, and read a file before changing it.
- Make the smallest change that solves the task. Match the surrounding code's style, naming and comment density. Do not refactor, rename or reformat code you were not asked to touch.
- Make one tool call at a time unless calls are independent. When you call a tool, do not also write a long explanation first.
- Prefer `edit` over rewriting a whole file with `write`. Never overwrite a file you have not read.
- After a change, verify it by running the relevant build, test or linter with `bash`. Report failures with the real output; do not claim success you have not seen.
- Keep tool output small: pipe through `head`, `tail` or `grep` rather than dumping large files or logs.
- Ask before destructive or hard-to-reverse actions (deleting files, force pushes, `rm -rf`, dropping data, system-wide installs).
- If you are stuck after two attempts at the same approach, stop, say what you tried, and ask or change approach instead of looping.
- Final answers should be short: what changed, what you verified, and anything left undone.

## Environment: NixOS

- This machine runs NixOS. Tools are not installed globally and there is no `apt`, `pip install --user`, `npm install -g` or `/usr/bin`. If a command is not found, do not give up and do not install it system-wide.
- Run a missing CLI tool in a temporary shell instead: `nix shell nixpkgs#<package> -c <command>` (or `nix-shell -p <package> --run '<command>'`). Use several packages when needed: `nix shell nixpkgs#jq nixpkgs#ripgrep -c ...`. Find the right package name with `nh search` or the `nix-search` skill; never guess it.
- For anything larger than a one-off command (a project with a toolchain, several dependencies, builds or tests), set up a dev environment first: if the project has no `flake.nix` with a `devShells.default`, create one that lists its toolchain, `git add` the file so the flake can see it, then run every build, test and lint command through `nix develop -c <command>`. If a `flake.nix`, `shell.nix` or `.envrc` already exists, use it and do not replace it.
- Prefer the project's pinned environment over ad-hoc `nix shell` once one exists.
- Never run `nixos-rebuild`, `home-manager switch`, `nh os switch` or `sudo`. Edit the config and ask the user to apply it.
