/**
 * Tokens/s Extension - shows output speed in the status bar
 *
 * While the model streams, the status bar shows live output tokens/s:
 * - Providers that report usage mid-stream use that count.
 * - Otherwise the estimate is derived from streamed delta characters
 *   (roughly 4 characters per token).
 * - When the message ends, the exact rate (usage.output over the
 *   response duration, including time-to-first-token) is shown briefly.
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "tokens-per-second";
const CHARS_PER_TOKEN = 4;
const MIN_ELAPSED_SECONDS = 0.2;
const STATUS_THROTTLE_MS = 200;
const FINAL_HOLD_MS = 3000;

const fmtTokens = (n: number) => (n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${Math.round(n)}`);

export default function (pi: ExtensionAPI) {
	let active = false;
	let startMs = 0;
	let streamChars = 0;
	let lastStatusUpdate = 0;
	let finalTimer: ReturnType<typeof setTimeout> | undefined;

	const render = (tokens: number, seconds: number) =>
		`⚡ ${(tokens / seconds).toFixed(1)} tok/s · ${fmtTokens(tokens)} out`;

	pi.on("message_start", async (event) => {
		if (event.message.role !== "assistant") return;
		const msg = event.message as AssistantMessage;
		startMs = Number.isFinite(msg.timestamp) && msg.timestamp > 0 ? msg.timestamp : Date.now();
		streamChars = 0;
		lastStatusUpdate = 0;
		active = true;
	});

	pi.on("message_update", async (event, ctx) => {
		if (event.message.role !== "assistant" || !active) return;

		const se = event.assistantMessageEvent;
		if (se.type === "text_delta" || se.type === "thinking_delta" || se.type === "toolcall_delta") {
			streamChars += se.delta.length;
		}

		const now = Date.now();
		if (now - lastStatusUpdate < STATUS_THROTTLE_MS) return;

		const reported = (event.message as AssistantMessage).usage?.output ?? 0;
		const tokens = Math.max(reported, streamChars / CHARS_PER_TOKEN);
		const seconds = (now - startMs) / 1000;
		if (seconds < MIN_ELAPSED_SECONDS || tokens <= 0) return;

		lastStatusUpdate = now;
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, render(tokens, seconds));
	});

	pi.on("message_end", async (event, ctx) => {
		if (event.message.role !== "assistant") return;
		const msg = event.message as AssistantMessage;
		active = false;
		streamChars = 0;

		if (finalTimer) {
			clearTimeout(finalTimer);
			finalTimer = undefined;
		}

		const seconds =
			msg.durationMs && msg.durationMs > 0 ? msg.durationMs / 1000 : (Date.now() - startMs) / 1000;
		const out = msg.usage?.output ?? 0;

		if (ctx.hasUI && out > 0 && seconds >= MIN_ELAPSED_SECONDS) {
			ctx.ui.setStatus(STATUS_KEY, render(out, seconds));
		}

		finalTimer = setTimeout(() => {
			finalTimer = undefined;
			if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
		}, FINAL_HOLD_MS);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (finalTimer) {
			clearTimeout(finalTimer);
			finalTimer = undefined;
		}
		active = false;
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
	});
}
