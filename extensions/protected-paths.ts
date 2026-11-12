/**
 * Protected Paths: blocks the write and edit tools from touching secrets,
 * VCS internals and generated or machine-specific files. Adapted from Pi's
 * example of the same name.
 *
 * This only guards the write and edit tools. A bash command can still modify
 * these paths; permission-gate covers the destructive ones.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const protectedPaths = [
		".env",
		".git/",
		"node_modules/",
		".ssh/",
		".gnupg/",
		".pi/agent/auth.json",
		"flake.lock",
		"hardware-configuration.nix",
		"secrets/",
		".age",
		"id_ed25519",
		"id_rsa",
	];

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") return undefined;

		const path = event.input.path as string;
		if (!protectedPaths.some((p) => path.includes(p))) return undefined;

		if (ctx.hasUI) ctx.ui.notify(`Blocked write to protected path: ${path}`, "warning");
		return { block: true, reason: `Path "${path}" is protected; ask the user to change it.` };
	});
}
