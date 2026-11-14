# Ablation: the full config without the appended system prompt (system/append.md).
PI_ARGS=(
	-e /harness/extensions/nix.ts
	-e /harness/extensions/protected-paths.ts
	-e /harness/extensions/todo.ts
	-e /harness/extensions/git-checkpoint.ts
	-e /harness/node_modules/@juicesharp/rpiv-ask-user-question/index.ts
	--skill /harness/skills
)
