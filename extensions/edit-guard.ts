/**
 * Edit Guard: stops the model from overwriting an existing file with `write`.
 * Small files may still be rewritten; larger ones must use `edit`, which
 * changes only what is needed and cannot silently drop unrelated lines.
 * New files are always allowed.
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MAX_REWRITE_LINES = 40;

export default function (pi: ExtensionAPI) {
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write") return undefined;

		const path = event.input.path as string;
		const file = isAbsolute(path) ? path : resolve(ctx.cwd, path);

		let lines = 0;
		try {
			if (!existsSync(file) || !statSync(file).isFile()) return undefined;
			lines = readFileSync(file, "utf-8").split("\n").length;
		} catch {
			return undefined; // unreadable: let the write tool report the real error
		}
		if (lines <= MAX_REWRITE_LINES) return undefined;

		if (ctx.hasUI) ctx.ui.notify(`Blocked overwrite of ${path} (${lines} lines); use edit`, "warning");
		return {
			block: true,
			reason:
				`"${path}" already exists (${lines} lines). Do not overwrite it with write. ` +
				`Use the edit tool to change only the lines you need. ` +
				`Read the file first if you have not, then make one edit per change.`,
		};
	});
}
