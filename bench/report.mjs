#!/usr/bin/env node
/**
 * Aggregate results.jsonl into a per-config summary and a per-task pass matrix.
 *
 * Usage: report.mjs <results.jsonl> [--json]
 */

import { readFileSync } from "node:fs";

const [file, flag] = process.argv.slice(2);
const rows = readFileSync(file, "utf8")
	.split("\n")
	.filter((l) => l.trim())
	.map((l) => JSON.parse(l));

const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0);
const sd = (xs) => {
	if (xs.length < 2) return 0;
	const mu = mean(xs);
	return Math.sqrt(xs.reduce((a, x) => a + (x - mu) ** 2, 0) / (xs.length - 1));
};

const configs = [...new Set(rows.map((r) => r.config))];
const tasks = [...new Set(rows.map((r) => r.task))].sort();

const summary = configs.map((config) => {
	const all = rows.filter((r) => r.config === config);
	// Infra errors (no model reply) say nothing about the harness, so they leave the denominator.
	const rs = all.filter((r) => r.status !== "error");
	// Pass rate per run index, so the spread reflects run-to-run noise on the same task set.
	const runs = [...new Set(rs.map((r) => r.run))];
	const perRun = runs.map((run) => mean(rs.filter((r) => r.run === run).map((r) => (r.pass ? 1 : 0))));
	return {
		config,
		trials: all.length,
		pass_rate: mean(rs.map((r) => (r.pass ? 1 : 0))),
		pass_rate_sd_across_runs: sd(perRun),
		timeouts: rs.filter((r) => r.timed_out).length,
		infra_errors: all.length - rs.length,
		mean_wall_s: mean(rs.map((r) => r.wall_s)),
		mean_turns: mean(rs.map((r) => r.metrics?.turns ?? 0)),
		mean_output_tokens: mean(rs.map((r) => r.metrics?.output_tokens ?? 0)),
		// Prompt tokens including cache hits: llama.cpp reports reused prefix tokens as cacheRead.
		mean_input_tokens: mean(rs.map((r) => (r.metrics?.input_tokens ?? 0) + (r.metrics?.cache_read_tokens ?? 0))),
		mean_tool_calls: mean(rs.map((r) => r.metrics?.tool_calls ?? 0)),
		mean_tool_errors: mean(rs.map((r) => r.metrics?.tool_errors ?? 0)),
	};
});

const matrix = tasks.map((task) => {
	const row = { task };
	for (const config of configs) {
		const rs = rows.filter((r) => r.config === config && r.task === task);
		row[config] = `${rs.filter((r) => r.pass).length}/${rs.length}`;
	}
	return row;
});

if (flag === "--json") {
	process.stdout.write(`${JSON.stringify({ summary, matrix }, null, 2)}\n`);
	process.exit(0);
}

const pct = (x) => `${(x * 100).toFixed(1)}%`;
console.log("Per config");
console.table(
	Object.fromEntries(
		summary.map((s) => [
			s.config,
			{
				trials: s.trials,
				pass: pct(s.pass_rate),
				"±sd(runs)": pct(s.pass_rate_sd_across_runs),
				timeouts: s.timeouts,
				infra_err: s.infra_errors,
				wall_s: s.mean_wall_s.toFixed(0),
				turns: s.mean_turns.toFixed(1),
				out_tok: s.mean_output_tokens.toFixed(0),
				in_tok: s.mean_input_tokens.toFixed(0),
				tools: s.mean_tool_calls.toFixed(1),
				tool_err: s.mean_tool_errors.toFixed(1),
			},
		]),
	),
);
console.log("\nPasses per task");
console.table(Object.fromEntries(matrix.map(({ task, ...rest }) => [task, rest])));
