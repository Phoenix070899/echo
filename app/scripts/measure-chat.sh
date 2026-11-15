#!/bin/sh
# Measures how long a chat line takes from being written to the transcript to reaching Echo's chat,
# the way Echo reads it: polling every 800 ms (before features/0088) and the held read (after).
# It runs its own daemon, state folder, and throwaway repo, never the human's, and cleans up.
#
#   app/scripts/measure-chat.sh [messages]
#
# Each message the fake agent gets writes two lines: the human's at once, its reply 2 s later.
# Prints, for each way of reading, the median and the slowest of every line's delay.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
COUNT=${1:-10}
E="$ROOT/target/release/echoctl"
STATE=/tmp/hubchat
WORK=$(mktemp -d /tmp/hubchat-work.XXXXXX)
REPO="$WORK/zzchat"
export HUB_STATE="$STATE" HUB_TEST_AGENT="$ROOT/crates/hub/tests/fake-agent.sh"
export CLAUDE_CONFIG_DIR="$STATE/claude" HUB_FAKE_CHAT="$STATE/chat.jsonl"

[ -x "$E" ] || { echo "build the daemon first: cargo build --release" >&2; exit 1; }
[ ! -e "$STATE" ] || { echo "$STATE exists; another run is going, or remove it" >&2; exit 1; }

cleanup() {
    "$E" shutdown --force >/dev/null 2>&1 || true
    rm -rf "$STATE" "$WORK"
}
trap cleanup EXIT INT TERM

mkdir -p "$REPO" && git -C "$REPO" init -q && git -C "$REPO" commit -q --allow-empty -m init
cd "$REPO"
"$E" status >/dev/null

python3 -I - "$STATE" "$REPO" "$COUNT" <<'EOF'
import json, os, socket, statistics, sys, threading, time

state, repo, count = sys.argv[1], os.path.realpath(sys.argv[2]), int(sys.argv[3])

def call(method, params):
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(state + "/hubd.sock")
        s.sendall((json.dumps({"method": method, "params": params}) + "\n").encode())
        reply = json.loads(s.makefile().readline())
    if not reply.get("ok"):
        raise SystemExit(f"{method}: {reply.get('error')}")
    return reply["result"]

agent = call("agent.open", {"repo": repo, "kind": "orchestrator", "name": "chat"})["agent"]
session = call("chat.read", {"agent": agent})["session"]
chat = state + "/chat.jsonl"
open(chat, "w").close()
projects = f"{state}/claude/projects/{os.path.basename(repo)}"
os.makedirs(projects, exist_ok=True)
os.symlink(chat, f"{projects}/{session}.jsonl")

# The fake agent's first screen.
time.sleep(2)

def measure(held):
    written, seen = {}, {}
    stop = threading.Event()

    # When each line reached the file, by its count of lines.
    def watch():
        lines = 0
        while not stop.is_set():
            with open(chat) as f:
                n = f.read().count("\n")
            for line in range(lines, n):
                written[line] = time.time()
            lines = n
            time.sleep(0.001)

    # Echo's loop: the first read at once, then each held (after) or every 800 ms (before).
    def read():
        last = call("chat.read", {"agent": agent})
        total = len(last["items"])
        while not stop.is_set():
            params = {"agent": agent, "session": session, "after": last["end"]}
            if held:
                params.update(state=last["state"], wait=2000)
            last = call("chat.read", params)
            for _ in last["items"]:
                seen[total] = time.time()
                total += 1
            if not held:
                time.sleep(0.8)

    start = len(open(chat).read().splitlines())
    threads = [threading.Thread(target=watch, daemon=True), threading.Thread(target=read, daemon=True)]
    for t in threads:
        t.start()
    time.sleep(0.5)
    for n in range(count):
        call("chat.send", {"agent": agent, "text": f"message {n}"})
        time.sleep(2.5 + (n % 4) * 0.2)
    time.sleep(3)
    stop.set()
    for t in threads:
        t.join()
    delays = [(seen[i] - written[i]) * 1000 for i in written if i >= start and i in seen]
    missed = sum(1 for i in written if i >= start and i not in seen)
    name = "held read (after)" if held else "800 ms poll (before)"
    print(f"{name}: {len(delays)} lines, median {statistics.median(delays):.0f} ms, "
          f"slowest {max(delays):.0f} ms" + (f", {missed} never seen" if missed else ""))

measure(held=False)
measure(held=True)
EOF
