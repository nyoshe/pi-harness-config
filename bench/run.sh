#!/usr/bin/env bash
# Run benchmark tasks against harness configs, each trial in its own bubblewrap sandbox.
# See bench/README.md.
set -euo pipefail

BENCH_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$BENCH_DIR")

usage() {
	cat <<'EOF'
Usage: bench/run.sh [options]

  -c, --config NAME     Harness config from bench/configs/NAME.sh (repeatable; default: baseline, full)
  -k, --runs N          Repeats of every task x config (default: 1)
  -t, --tasks GLOB      Task directory name glob (default: *)
  -o, --out DIR         Results directory (default: bench/results/<timestamp>)
  -m, --model ID        llama.cpp model ID (default: defaultModel from ~/.pi/agent/settings.json)
  -u, --upstream URL    llama.cpp server (default: $LLAMA_BASE_URL, then ~/.pi/agent/auth.json)
      --allow-load      Run even if the model is not loaded on the router (it may swap models)
      --memory SIZE     Memory cap per sandbox (default: 16G)
      --shell TASK      Open an interactive shell in TASK's agent sandbox instead of running Pi
  -h, --help            Show this help
EOF
}

die() {
	echo "bench: $*" >&2
	exit 1
}
log() { echo "bench: $*" >&2; }

CONFIGS=()
RUNS=1
TASK_GLOB='*'
OUT=""
MODEL=""
UPSTREAM="${LLAMA_BASE_URL:-}"
ALLOW_LOAD=0
MEMORY=16G
SHELL_TASK=""

while (($#)); do
	case "$1" in
	-c | --config) CONFIGS+=("$2"); shift 2 ;;
	-k | --runs) RUNS="$2"; shift 2 ;;
	-t | --tasks) TASK_GLOB="$2"; shift 2 ;;
	-o | --out) OUT="$2"; shift 2 ;;
	-m | --model) MODEL="$2"; shift 2 ;;
	-u | --upstream) UPSTREAM="$2"; shift 2 ;;
	--allow-load) ALLOW_LOAD=1; shift ;;
	--memory) MEMORY="$2"; shift 2 ;;
	--shell) SHELL_TASK="$2"; shift 2 ;;
	-h | --help) usage; exit 0 ;;
	*) usage >&2; die "unknown option: $1" ;;
	esac
done

((${#CONFIGS[@]})) || CONFIGS=(baseline full)
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || die "--runs must be a positive integer"

# ── Host tools ────────────────────────────────────────────────────────────────

for tool in bwrap node jq nix pi git timeout socat; do
	command -v "$tool" >/dev/null || die "missing host tool: $tool (try: nix run .#bench)"
done

store_bin() { dirname "$(readlink -f "$(command -v "$1")")"; }
PI_BIN=$(store_bin pi)
NIX_BIN=$(store_bin nix)
SOCAT=$(readlink -f "$(command -v socat)")
PI_VERSION=$(pi --version 2>/dev/null || echo unknown)

if bwrap --unshare-all --ro-bind /nix/store /nix/store "$(readlink -f "$BASH")" -c : 2>/dev/null; then :; else
	die "bubblewrap cannot create unprivileged namespaces on this machine"
fi

LIMIT=()
if command -v systemd-run >/dev/null && systemd-run --user --scope --quiet true 2>/dev/null; then
	LIMIT=(systemd-run --user --scope --quiet --collect -p "MemoryMax=$MEMORY" -p TasksMax=2048)
else
	log "warning: systemd user scopes unavailable; running without memory/task limits"
fi

# ── Model and upstream ────────────────────────────────────────────────────────

AGENT_SETTINGS="$HOME/.pi/agent/settings.json"
AGENT_AUTH="$HOME/.pi/agent/auth.json"
[[ -n "$MODEL" ]] || MODEL=$(jq -r '.defaultModel // empty' "$AGENT_SETTINGS" 2>/dev/null || true)
[[ -n "$MODEL" ]] || die "no model: pass --model"
[[ -n "$UPSTREAM" ]] || UPSTREAM=$(jq -r '.["llama.cpp"].env.LLAMA_BASE_URL // empty' "$AGENT_AUTH" 2>/dev/null || true)
[[ -n "$UPSTREAM" ]] || UPSTREAM=http://127.0.0.1:8080
UPSTREAM=${UPSTREAM%/}

if [[ -z "$SHELL_TASK" ]]; then
	health=$(node -e 'fetch(process.argv[1]+"/health").then(r=>r.text()).then(t=>console.log(t),e=>{console.error(e.message);process.exit(1)})' "$UPSTREAM") ||
		die "llama.cpp server not reachable at $UPSTREAM"
	log "upstream $UPSTREAM: $health"
	status=$(node -e '
		fetch(process.argv[1]+"/models").then(r=>r.ok?r.json():null).then(j=>{
			const m=(j?.data??[]).find(m=>m.id===process.argv[2]);
			console.log(j===null?"no-router":m?(m.status?.value??"unknown"):"missing");
		},()=>console.log("no-router"))' "$UPSTREAM" "$MODEL")
	case "$status" in
	loaded | no-router) ;;
	missing) die "model not on router: $MODEL" ;;
	*) ((ALLOW_LOAD)) || die "model $MODEL is '$status' on the router; load it first or pass --allow-load" ;;
	esac
fi

# A fresh agent dir does not discover llama.cpp models, so seed it with the host's model
# store, pointed at the in-sandbox bridge. This also pins the model metadata for the run.
MODEL_STORE=$(jq -c --arg model "$MODEL" '
	{"llama.cpp": (.["llama.cpp"] | .models |= map(.baseUrl = "http://127.0.0.1:8080/v1"))}
	| select(any(.["llama.cpp"].models[]; .id == $model))' "$HOME/.pi/agent/models-store.json" 2>/dev/null || true)
[[ -n "$MODEL_STORE" ]] ||
	die "$MODEL is not in ~/.pi/agent/models-store.json; select it once in interactive Pi (/model) so Pi records it"

# ── Nix packages ──────────────────────────────────────────────────────────────

# Resolved from the host's flake registry, which the sandbox shares read-only, so
# `nix shell nixpkgs#<pkg>` inside the sandbox finds the same store paths.
declare -A PKG_BIN=()
resolve_pkgs() {
	local p paths bins
	for p in "$@"; do
		[[ -n "${PKG_BIN[$p]+x}" ]] && continue
		paths=$(nix build --no-link --print-out-paths "nixpkgs#$p") || die "cannot build nixpkgs#$p"
		bins=""
		while read -r out; do [[ -d "$out/bin" ]] && bins+="${bins:+:}$out/bin"; done <<<"$paths"
		PKG_BIN[$p]=$bins
	done
}
pkg_path() {
	local p acc=""
	for p in "$@"; do [[ -n "${PKG_BIN[$p]}" ]] && acc+="${acc:+:}${PKG_BIN[$p]}"; done
	echo "$acc"
}

BASE_PKGS=(bashInteractive coreutils findutils gnugrep gnused gawk diffutils gnupatch gitMinimal ripgrep fd jq which procps gnutar gzip file)
log "resolving base packages"
resolve_pkgs "${BASE_PKGS[@]}"
BASE_PATH="$(pkg_path "${BASE_PKGS[@]}"):$NIX_BIN"
SANDBOX_SH="${PKG_BIN[bashInteractive]%%:*}/bash"
SANDBOX_ENV="${PKG_BIN[coreutils]%%:*}/env"

NIX_PATH_SANDBOX=""
[[ -e /etc/nixpkgs/channels/nixpkgs ]] && NIX_PATH_SANDBOX="nixpkgs=/etc/nixpkgs/channels/nixpkgs"

# ── Sandbox ───────────────────────────────────────────────────────────────────

# Args shared by agent and verify sandboxes. No network namespace is shared, the Nix store
# is read-only and the daemon socket is hidden: this user is a trusted Nix user, so daemon
# access would be root-equivalent.
sandbox_args() {
	local trial=$1 path=$2
	local -n _out=$3
	_out=(
		--unshare-all --die-with-parent --clearenv
		--ro-bind /nix /nix
		--tmpfs /nix/var/nix/daemon-socket
		--proc /proc --dev /dev --tmpfs /tmp
		--ro-bind "$trial/etc/passwd" /etc/passwd
		--ro-bind "$trial/etc/group" /etc/group
		--symlink "$SANDBOX_SH" /bin/sh
		--symlink "$SANDBOX_SH" /bin/bash
		--symlink "$SANDBOX_ENV" /usr/bin/env
		--bind "$trial/home" /home/bench
		--bind "$trial/work" /work
		--chdir /work
		--setenv HOME /home/bench --setenv USER bench --setenv LOGNAME bench
		--setenv PATH "$path"
		--setenv TERM dumb --setenv LANG C.UTF-8 --setenv TMPDIR /tmp
		--setenv GIT_CONFIG_GLOBAL /home/bench/.gitconfig
		--setenv NIX_REMOTE 'local?read-only=true'
		--setenv NIX_CONFIG $'extra-experimental-features = nix-command flakes read-only-local-store\nflake-registry ='
	)
	[[ -d /etc/nix ]] && _out+=(--ro-bind /etc/nix /etc/nix)
	[[ -d /etc/static ]] && _out+=(--ro-bind /etc/static /etc/static)
	if [[ -n "$NIX_PATH_SANDBOX" ]]; then
		_out+=(--ro-bind /etc/nixpkgs /etc/nixpkgs --setenv NIX_PATH "$NIX_PATH_SANDBOX")
	fi
	return 0
}

# Runs inside the agent sandbox: bridge 127.0.0.1:8080 to the proxy socket, then start Pi.
# shellcheck disable=SC2016
AGENT_SCRIPT='
"$BENCH_SOCAT" TCP-LISTEN:8080,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/run/bench/model.sock 2>/dev/null &
for _ in $(seq 100); do (exec 3<>/dev/tcp/127.0.0.1/8080) 2>/dev/null && break; sleep 0.1; done
if [[ -n "${BENCH_SHELL:-}" ]]; then exec bash -i; fi
exec "$BENCH_PI" --print --mode json --provider llama.cpp --model "$BENCH_MODEL" \
	--session-dir /home/bench/sessions --no-mcp "$@" "$(cat /run/bench/instruction.md)"
'

# ── Trials ────────────────────────────────────────────────────────────────────

prepare_trial() {
	local trial=$1 task_dir=$2
	mkdir -p "$trial"/{etc,home/.pi/agent,work}
	# Unix socket paths are capped at 108 bytes, so the socket dir lives under a short path.
	[[ -n "${RUN_DIR:-}" ]] && rm -rf "$RUN_DIR"
	RUN_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/pibench.XXXXXX")
	echo "bench:x:$(id -u):$(id -g):bench:/home/bench:/bin/sh" >"$trial/etc/passwd"
	echo "bench:x:$(id -g):" >"$trial/etc/group"
	printf '[user]\n\tname = bench\n\temail = bench@localhost\n[init]\n\tdefaultBranch = main\n' >"$trial/home/.gitconfig"
	jq -n --arg model "$MODEL" '{defaultProvider: "llama.cpp", defaultModel: $model, quietStartup: true}' \
		>"$trial/home/.pi/agent/settings.json"
	echo "$MODEL_STORE" >"$trial/home/.pi/agent/models-store.json"
	echo '{"llama.cpp":{"type":"api_key","env":{"LLAMA_BASE_URL":"http://127.0.0.1:8080"}}}' \
		>"$trial/home/.pi/agent/auth.json"

	[[ -d "$task_dir/files" ]] && cp -a "$task_dir/files/." "$trial/work/"
	git -C "$trial/work" -c init.defaultBranch=main init -q
	git -C "$trial/work" -c user.name=bench -c user.email=bench@localhost add -A
	git -C "$trial/work" -c user.name=bench -c user.email=bench@localhost commit -q --allow-empty -m "Initial task state"
	# Verify compares against this commit, which the agent cannot rewrite (unlike HEAD).
	BASE_SHA=$(git -C "$trial/work" rev-parse HEAD)

	if [[ -f "$task_dir/instruction.md" ]]; then
		cp "$task_dir/instruction.md" "$RUN_DIR/instruction.md"
	else
		jq -r '.instruction' "$task_dir/task.json" >"$RUN_DIR/instruction.md"
	fi
}

start_proxy() {
	local trial=$1
	node "$BENCH_DIR/model-proxy.mjs" "$RUN_DIR/model.sock" "$UPSTREAM" "$trial/proxy.log" "$MODEL" &
	PROXY_PID=$!
	for _ in $(seq 50); do [[ -S "$RUN_DIR/model.sock" ]] && return 0; sleep 0.1; done
	die "model proxy did not start (see $trial/proxy.log)"
}
stop_proxy() {
	[[ -n "${PROXY_PID:-}" ]] || return 0
	kill "$PROXY_PID" 2>/dev/null || true
	wait "$PROXY_PID" 2>/dev/null || true
	PROXY_PID=""
}
cleanup() {
	stop_proxy
	[[ -n "${RUN_DIR:-}" ]] && rm -rf "$RUN_DIR"
	return 0
}
trap cleanup EXIT

load_config() {
	local name=$1 file="$BENCH_DIR/configs/$1.sh"
	[[ -f "$file" ]] || die "no config: $file"
	PI_ARGS=()
	HARNESS="$REPO_DIR"
	# shellcheck disable=SC1090
	source "$file"
	HARNESS=$(cd "$HARNESS" && pwd)
	if printf '%s\n' "${PI_ARGS[@]}" | grep -q '^/harness/node_modules/' && [[ ! -d "$HARNESS/node_modules" ]]; then
		die "config $name loads bundled packages but $HARNESS/node_modules is missing; run npm ci there"
	fi
	HARNESS_REV=$(git -C "$HARNESS" rev-parse --short HEAD 2>/dev/null || echo none)
	git -C "$HARNESS" diff --quiet HEAD 2>/dev/null || HARNESS_REV+="-dirty"
}

load_task() {
	local task_dir=$1
	TASK_TIMEOUT=$(jq -r '.timeout // 900' "$task_dir/task.json")
	mapfile -t TASK_PKGS < <(jq -r '.packages // [] | .[]' "$task_dir/task.json")
	mapfile -t TASK_PREWARM < <(jq -r '.prewarm // [] | .[]' "$task_dir/task.json")
	mapfile -t TASK_VERIFY_PKGS < <(jq -r '.verify_packages // [] | .[]' "$task_dir/task.json")
	resolve_pkgs "${TASK_PKGS[@]}" "${TASK_PREWARM[@]}" "${TASK_VERIFY_PKGS[@]}"
	AGENT_PATH="$(pkg_path "${TASK_PKGS[@]}")"
	AGENT_PATH="${AGENT_PATH:+$AGENT_PATH:}$BASE_PATH"
	VERIFY_PATH="$(pkg_path "${TASK_PKGS[@]}" "${TASK_VERIFY_PKGS[@]}")"
	VERIFY_PATH="${VERIFY_PATH:+$VERIFY_PATH:}$BASE_PATH"
}

agent_bwrap() {
	local trial=$1
	local -a args
	sandbox_args "$trial" "$AGENT_PATH" args
	AGENT_CMD=(bwrap "${args[@]}")
	# Only the package's own resources: the checkout also holds bench/ (hidden tests, earlier
	# trials' results) and .git (which has the tests as blobs).
	local entry
	for entry in package.json extensions skills system prompts node_modules; do
		[[ -e "$HARNESS/$entry" ]] && AGENT_CMD+=(--ro-bind "$HARNESS/$entry" "/harness/$entry")
	done
	AGENT_CMD+=(
		--bind "$RUN_DIR" /run/bench
		--setenv PI_CODING_AGENT_DIR /home/bench/.pi/agent
		--setenv LLAMA_BASE_URL http://127.0.0.1:8080
		--setenv BENCH_SOCAT "$SOCAT" --setenv BENCH_PI "$PI_BIN/pi" --setenv BENCH_MODEL "$MODEL"
	)
}

run_trial() {
	local config=$1 task_dir=$2 run=$3
	local task trial start end agent_exit=0 verify_exit=0 timed_out=false
	task=$(basename "$task_dir")
	trial="$OUT/trials/$config/$task/run$run"
	rm -rf "$trial"
	prepare_trial "$trial" "$task_dir"

	agent_bwrap "$trial"
	start_proxy "$trial"
	start=$(date +%s.%N)
	timeout --kill-after=15 "$TASK_TIMEOUT" "${LIMIT[@]}" "${AGENT_CMD[@]}" --new-session \
		"$SANDBOX_SH" -c "$AGENT_SCRIPT" bench-agent "${PI_ARGS[@]}" \
		</dev/null >"$trial/pi.jsonl" 2>"$trial/agent.stderr.log" || agent_exit=$?
	end=$(date +%s.%N)
	stop_proxy
	((agent_exit == 124 || agent_exit == 137)) && timed_out=true

	# Hidden tests arrive only after the agent has exited.
	local -a vargs
	if [[ -d "$task_dir/verify" ]]; then
		cp -a "$task_dir/verify" "$trial/verify"
		sandbox_args "$trial" "$VERIFY_PATH" vargs
		timeout --kill-after=10 300 "${LIMIT[@]}" bwrap "${vargs[@]}" --ro-bind "$trial/verify" /verify \
			--setenv BENCH_BASE_SHA "$BASE_SHA" --new-session \
			"$SANDBOX_SH" /verify/verify.sh </dev/null >"$trial/verify.log" 2>&1 || verify_exit=$?
	else
		echo "task has no verify/ directory" >"$trial/verify.log"
		verify_exit=1
	fi

	local metrics status=ok
	metrics=$(node "$BENCH_DIR/summarize.mjs" "$trial/pi.jsonl")
	if [[ "$timed_out" == true ]]; then
		status=timeout
	elif [[ $(jq '.assistant_messages' <<<"$metrics") == 0 ]]; then
		status=error
	fi

	jq -nc \
		--arg config "$config" --arg task "$task" --argjson run "$run" \
		--argjson pass "$([[ $verify_exit == 0 ]] && echo true || echo false)" \
		--argjson verify_exit "$verify_exit" --argjson agent_exit "$agent_exit" \
		--argjson timed_out "$timed_out" --arg status "$status" \
		--argjson wall_s "$(awk "BEGIN{printf \"%.1f\", $end - $start}")" \
		--arg model "$MODEL" --arg harness "$HARNESS" --arg harness_rev "$HARNESS_REV" \
		--arg pi_version "$PI_VERSION" --arg trial "$trial" \
		--arg timestamp "$(date -Iseconds)" --argjson metrics "$metrics" \
		'{config:$config, task:$task, run:$run, pass:$pass, status:$status, timed_out:$timed_out,
		  verify_exit:$verify_exit, agent_exit:$agent_exit, wall_s:$wall_s, model:$model,
		  harness:$harness, harness_rev:$harness_rev, pi_version:$pi_version,
		  timestamp:$timestamp, trial:$trial, metrics:$metrics}' |
		tee "$trial/result.json" >>"$OUT/results.jsonl"

	log "$(printf '%-12s %-28s run%-3s %s  %ss  turns=%s out_tok=%s' \
		"$config" "$task" "$run" "$([[ $verify_exit == 0 ]] && echo PASS || echo "FAIL($status)")" \
		"$(jq -r .wall_s "$trial/result.json")" "$(jq .turns <<<"$metrics")" "$(jq .output_tokens <<<"$metrics")")"
}

# ── Main ──────────────────────────────────────────────────────────────────────

[[ -n "$OUT" ]] || OUT="$BENCH_DIR/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

if [[ -n "$SHELL_TASK" ]]; then
	task_dir="$BENCH_DIR/tasks/$SHELL_TASK"
	[[ -f "$task_dir/task.json" ]] || die "no task: $task_dir"
	load_config "${CONFIGS[0]}"
	load_task "$task_dir"
	trial="$OUT/shell"
	rm -rf "$trial"
	prepare_trial "$trial" "$task_dir"
	agent_bwrap "$trial"
	start_proxy "$trial"
	log "shell in $SHELL_TASK sandbox (config ${CONFIGS[0]}); exit to leave. Trial dir: $trial"
	"${AGENT_CMD[@]}" --setenv BENCH_SHELL 1 "$SANDBOX_SH" -c "$AGENT_SCRIPT" bench-shell || true
	exit 0
fi

mapfile -t TASK_DIRS < <(find "$BENCH_DIR/tasks" -mindepth 1 -maxdepth 1 -type d -name "$TASK_GLOB" | sort)
((${#TASK_DIRS[@]})) || die "no tasks match '$TASK_GLOB'"
for c in "${CONFIGS[@]}"; do [[ -f "$BENCH_DIR/configs/$c.sh" ]] || die "no config: $c"; done

log "model=$MODEL pi=$PI_VERSION configs=${CONFIGS[*]} tasks=${#TASK_DIRS[@]} runs=$RUNS out=$OUT"

# Interleave configs within each task and run, so drift on the shared server hits all configs alike.
for ((run = 1; run <= RUNS; run++)); do
	for task_dir in "${TASK_DIRS[@]}"; do
		load_task "$task_dir"
		for config in "${CONFIGS[@]}"; do
			load_config "$config"
			run_trial "$config" "$task_dir" "$run"
		done
	done
done

node "$BENCH_DIR/report.mjs" "$OUT/results.jsonl" | tee "$OUT/report.txt"
