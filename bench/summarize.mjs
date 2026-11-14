#!/usr/bin/env node
/**
 * Summarize one trial's `pi --mode json` stream into metrics.
 *
 * Usage: summarize.mjs <pi.jsonl>   (prints one JSON object)
 */

import { readFileSync } from "node:fs";

const file = process.argv[2];
let text = "";
try {
	text = readFileSync(file, "utf8");
} catch {}

const m = {
	turns: 0,
	assistant_messages: 0,
	input_tokens: 0,
	output_tokens: 0,
	cache_read_tokens: 0,
	tool_calls: 0,
	tool_errors: 0,
	tools: {},
	compactions: 0,
	settled: false,
	aborted: false,
	last_stop_reason: null,
	error: null,
	bad_lines: 0,
};

// Split on LF only: U+2028/U+2029 are valid inside JSON strings (see Pi's json.md).
for (const raw of text.split("\n")) {
	const line = raw.replace(/\r$/, "").trim();
	if (!line) continue;
	let ev;
	try {
		ev = JSON.parse(line);
	} catch {
		m.bad_lines++;
		continue;
	}
	switch (ev.type) {
		case "turn_end":
			m.turns++;
			break;
		case "message_end": {
			const msg = ev.message ?? {};
			if (msg.role !== "assistant") break;
			m.assistant_messages++;
			const u = msg.usage ?? {};
			m.input_tokens += u.input ?? 0;
			m.output_tokens += u.output ?? 0;
			m.cache_read_tokens += u.cacheRead ?? 0;
			m.last_stop_reason = msg.stopReason ?? null;
			if (msg.errorMessage) m.error = msg.errorMessage;
			break;
		}
		case "tool_execution_end":
			m.tool_calls++;
			m.tools[ev.toolName] = (m.tools[ev.toolName] ?? 0) + 1;
			if (ev.isError) m.tool_errors++;
			break;
		case "compaction_end":
			m.compactions++;
			break;
		case "agent_settled":
			m.settled = true;
			m.aborted = Boolean(ev.aborted);
			break;
	}
}

process.stdout.write(`${JSON.stringify(m)}\n`);
