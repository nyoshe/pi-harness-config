#!/usr/bin/env node
/**
 * Model proxy: the sandbox's only route out. Listens on a Unix socket that is bind-mounted
 * into the sandbox and forwards an allowlist of llama.cpp requests to the upstream server:
 * model listing, and inference for the benchmark's model only. Router load/unload, any other
 * endpoint and any request naming another model get 403 and are logged, so an agent (or a
 * Pi built-in) cannot make the shared router swap models.
 *
 * Usage: model-proxy.mjs <socket-path> <upstream-url> <log-file> <model-id>
 */

import { appendFileSync, rmSync } from "node:fs";
import http from "node:http";
import https from "node:https";

const [socketPath, upstreamUrl, logFile, modelId] = process.argv.slice(2);
if (!socketPath || !upstreamUrl || !logFile || !modelId) {
	console.error("usage: model-proxy.mjs <socket-path> <upstream-url> <log-file> <model-id>");
	process.exit(2);
}

const upstream = new URL(upstreamUrl);
const transport = upstream.protocol === "https:" ? https : http;
const MAX_BODY = 64 * 1024 * 1024;

const ALLOW_GET = /^\/(health|props|models|v1\/models)(\?.*)?$/;
// Every allowed POST must name the benchmark model.
const ALLOW_POST = /^\/(v1\/)?(chat\/completions|completions|embeddings|tokenize|detokenize|apply-template)$/;

function log(line) {
	appendFileSync(logFile, `${new Date().toISOString()} ${line}\n`);
}

function deny(res, why) {
	res.writeHead(403, { "content-type": "text/plain" });
	res.end(`blocked by bench model proxy: ${why}\n`);
}

function forward(req, res, body) {
	const headers = { ...req.headers, host: upstream.host };
	if (body) headers["content-length"] = String(body.length);
	const proxied = transport.request(
		{
			protocol: upstream.protocol,
			hostname: upstream.hostname,
			port: upstream.port,
			method: req.method,
			path: req.url,
			headers,
		},
		(upstreamRes) => {
			res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
			upstreamRes.pipe(res);
		},
	);
	proxied.on("error", (err) => {
		log(`ERROR ${req.method} ${req.url}: ${err.message}`);
		if (!res.headersSent) res.writeHead(502, { "content-type": "text/plain" });
		res.end(`upstream error: ${err.message}\n`);
	});
	proxied.end(body);
}

const server = http.createServer((req, res) => {
	if (req.method === "GET" && ALLOW_GET.test(req.url)) {
		log(`ALLOW GET ${req.url}`);
		forward(req, res);
		return;
	}
	if (req.method !== "POST" || !ALLOW_POST.test(req.url)) {
		log(`DENY ${req.method} ${req.url}`);
		deny(res, "endpoint not allowed");
		req.resume();
		return;
	}

	const chunks = [];
	let size = 0;
	req.on("data", (chunk) => {
		size += chunk.length;
		if (size > MAX_BODY) {
			log(`DENY POST ${req.url}: body over ${MAX_BODY} bytes`);
			deny(res, "body too large");
			req.destroy();
			return;
		}
		chunks.push(chunk);
	});
	req.on("end", () => {
		if (res.writableEnded) return;
		const body = Buffer.concat(chunks);
		let model;
		try {
			model = JSON.parse(body.toString("utf8")).model;
		} catch {
			log(`DENY POST ${req.url}: body is not JSON`);
			deny(res, "body is not JSON");
			return;
		}
		if (model !== modelId) {
			log(`DENY POST ${req.url} model=${JSON.stringify(model)}`);
			deny(res, `only ${modelId} may be used`);
			return;
		}
		log(`ALLOW POST ${req.url} model=${model}`);
		forward(req, res, body);
	});
});

rmSync(socketPath, { force: true });
server.listen(socketPath, () => log(`LISTEN ${socketPath} -> ${upstream.origin} model=${modelId}`));

for (const signal of ["SIGINT", "SIGTERM"]) {
	process.on(signal, () => {
		server.close();
		rmSync(socketPath, { force: true });
		process.exit(0);
	});
}
