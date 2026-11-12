/**
 * Permission Gate: asks before running dangerous bash commands, and blocks
 * them outright when there is no UI to ask. Adapted from Pi's example of the
 * same name, with NixOS-specific patterns added.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const dangerousPatterns = [
		/\brm\s+(-\w*[rf]\w*|--recursive|--force)/i,
		/\bsudo\b/i,
		/\b(chmod|chown)\b.*777/i,
		/\bdd\b.*\bof=/i,
		/\bmkfs\b/i,
		/\bgit\s+push\b.*(--force|-f\b)/i,
		/\bgit\s+(reset\s+--hard|clean\s+-\w*f)/i,
		/\bnixos-rebuild\s+(switch|boot|test)/i,
		/\bhome-manager\s+switch/i,
		/\bnix-collect-garbage/i,
		/\bnix\s+store\s+(delete|gc)/i,
		/\bsystemctl\s+(stop|disable|mask|restart)/i,
	];

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		if (!dangerousPatterns.some((p) => p.test(command))) return undefined;

		if (!ctx.hasUI) {
			return { block: true, reason: "Dangerous command blocked (no UI for confirmation)" };
		}

		const choice = await ctx.ui.select(`⚠️ Dangerous command:\n\n  ${command}\n\nAllow?`, ["Yes", "No"]);
		if (choice !== "Yes") return { block: true, reason: "Blocked by user" };

		return undefined;
	});
}
