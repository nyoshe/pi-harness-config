/**
 * Append System: appends system/append.md to Pi's default system prompt on every
 * agent start. Replaces ~/.pi/agent/APPEND_SYSTEM.md so the guidance lives in this repo.
 */

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	const file = join(dirname(fileURLToPath(import.meta.url)), "..", "system", "append.md");

	pi.on("before_agent_start", async (event) => {
		let text: string;
		try {
			text = readFileSync(file, "utf8").trim();
		} catch {
			return undefined;
		}
		return { systemPrompt: `${event.systemPrompt}\n\n${text}\n` };
	});
}
