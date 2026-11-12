/**
 * Nix tooling: evaluate, build, check and search without hand-writing nix CLI
 * flags. Output is truncated so a failed build cannot flood a small context.
 */

import { execFile } from "node:child_process";
import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";

const MAX_CHARS = 6000;
const TIMEOUT_MS = 10 * 60 * 1000;

// Keep the tail: Nix puts the actual error at the end of its output.
function tail(text: string): string {
	return text.length <= MAX_CHARS ? text : `[... truncated ...]\n${text.slice(-MAX_CHARS)}`;
}

function runNix(args: string[], cwd: string, signal?: AbortSignal): Promise<{ text: string; ok: boolean }> {
	return new Promise((resolve) => {
		execFile(
			"nix",
			["--extra-experimental-features", "nix-command flakes", ...args],
			{ cwd, signal, timeout: TIMEOUT_MS, maxBuffer: 32 * 1024 * 1024 },
			(error, stdout, stderr) => {
				const out = [stdout, stderr].filter(Boolean).join("\n").trim();
				resolve({ ok: !error, text: tail(out || (error ? String(error.message) : "(no output)")) });
			},
		);
	});
}

function toResult(r: { text: string; ok: boolean }) {
	return { content: [{ type: "text" as const, text: r.ok ? r.text : `FAILED:\n${r.text}` }], details: { ok: r.ok } };
}

const nixEval = defineTool({
	name: "nix_eval",
	label: "Nix Eval",
	description:
		"Evaluate a flake attribute or Nix expression and print the result as JSON. " +
		"Use it to inspect config values (e.g. `.#nixosConfigurations.host.config.services.foo.enable`) " +
		"without building anything.",
	parameters: Type.Object({
		attr: Type.Optional(Type.String({ description: "Flake attribute, e.g. .#packages.x86_64-linux.default.name" })),
		expr: Type.Optional(Type.String({ description: "Nix expression (used instead of attr)" })),
	}),
	async execute(_id, params, signal, _onUpdate, ctx) {
		if (!params.attr && !params.expr) return toResult({ ok: false, text: "Provide `attr` or `expr`." });
		const args = params.expr
			? ["eval", "--json", "--impure", "--expr", params.expr]
			: ["eval", "--json", params.attr!];
		return toResult(await runNix(args, ctx.cwd, signal));
	},
});

const nixBuild = defineTool({
	name: "nix_build",
	label: "Nix Build",
	description:
		"Build a flake output without creating a ./result symlink and print the store path. " +
		"Use it to check that a change compiles. Prefer `dry_run` for a fast check of what would be built.",
	parameters: Type.Object({
		installable: Type.String({ description: "Installable, e.g. .#default or .#nixosConfigurations.host.config.system.build.toplevel" }),
		dry_run: Type.Optional(Type.Boolean({ description: "Only show what would be built" })),
	}),
	async execute(_id, params, signal, _onUpdate, ctx) {
		const args = ["build", "--no-link", "--print-out-paths", "-L", params.installable];
		if (params.dry_run) args.push("--dry-run");
		return toResult(await runNix(args, ctx.cwd, signal));
	},
});

const nixFlakeCheck = defineTool({
	name: "nix_flake_check",
	label: "Nix Flake Check",
	description: "Run `nix flake check` in the current directory to validate the flake and its checks.",
	parameters: Type.Object({
		no_build: Type.Optional(Type.Boolean({ description: "Only evaluate, do not build checks" })),
	}),
	async execute(_id, params, signal, _onUpdate, ctx) {
		const args = ["flake", "check", "-L"];
		if (params.no_build) args.push("--no-build");
		return toResult(await runNix(args, ctx.cwd, signal));
	},
});

const nixSearch = defineTool({
	name: "nix_search",
	label: "Nix Search",
	description: "Search nixpkgs for packages by name or description. Returns package attribute names and descriptions.",
	parameters: Type.Object({
		query: Type.String({ description: "Search terms" }),
		limit: Type.Optional(Type.Number({ description: "Max results (default 15)" })),
	}),
	async execute(_id, params, signal, _onUpdate, ctx) {
		const r = await runNix(["search", "nixpkgs", params.query, "--json"], ctx.cwd, signal);
		if (!r.ok) return toResult(r);
		try {
			const data = JSON.parse(r.text) as Record<string, { pname: string; version: string; description: string }>;
			const lines = Object.entries(data)
				.slice(0, params.limit ?? 15)
				.map(([k, v]) => `${k.replace(/^legacyPackages\.[^.]+\./, "nixpkgs#")}  ${v.version}  ${v.description}`);
			return toResult({ ok: true, text: lines.join("\n") || "No results." });
		} catch {
			return toResult(r); // truncated JSON: fall back to raw output
		}
	},
});

export default function (pi: ExtensionAPI) {
	pi.registerTool(nixEval);
	pi.registerTool(nixBuild);
	pi.registerTool(nixFlakeCheck);
	pi.registerTool(nixSearch);
}
