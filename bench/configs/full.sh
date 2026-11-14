# This harness as used day to day, minus what cannot work or would skew a headless sandboxed run:
# - permission-gate: blocks every dangerous command when there is no UI; the sandbox is the guard here
# - pi-web-access: the sandbox has no internet, and web search would leak benchmark answers
# - pi-open-tui: TUI only, no effect in --print mode
# ask_user_question removes itself when there is no UI, so it is loaded for fidelity.
#
# Stock Pi built-ins stay on, as in baseline. Paths are inside the sandbox: /harness is
# $HARNESS (this checkout unless a config sets it).
PI_ARGS=(
	-e /harness/extensions/append-system.ts
	-e /harness/extensions/nix.ts
	-e /harness/extensions/protected-paths.ts
	-e /harness/extensions/todo.ts
	-e /harness/extensions/git-checkpoint.ts
	-e /harness/node_modules/@juicesharp/rpiv-ask-user-question/index.ts
	--skill /harness/skills
)
