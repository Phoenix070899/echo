#!/bin/sh
# Measures how much main-thread time Echo spends switching between agents in different checkouts.
# It runs a test copy of app/build/Echo.app on its own daemon, state folder, and throwaway repo,
# never the human's, and cleans up after itself.
#
#   app/scripts/measure-switch.sh [runs]
#
# FILES=1 switches with the Files column shown; WRITES=1 also has a file in the shown checkout
# written ten times a second during the idle measure, as an agent at work does. KEEP_SAMPLES=<folder> keeps the `sample` files. Prints, for each run of 30 switches, the busy main-thread samples (1 per ms, waiting time left
# out), then the median per switch. Single runs vary by 2 to 3 times (bugs/0055): compare medians.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
RUNS=${1:-5}
E="$ROOT/target/release/echoctl"
STATE=/tmp/hubbench
WORK=$(mktemp -d /tmp/hubbench-work.XXXXXX)
APP="$WORK/EchoBench.app"
REPO="$WORK/zzbench"
AGENT="$ROOT/crates/hub/tests/fake-agent.sh"
export HUB_STATE="$STATE" HUB_TEST_AGENT="$AGENT"

[ -x "$E" ] || { echo "build the daemon first: cargo build --release" >&2; exit 1; }
[ -d "$ROOT/app/build/Echo.app" ] || { echo "build the app first: make -C app app" >&2; exit 1; }
[ ! -e "$STATE" ] || { echo "$STATE exists; another run is going, or remove it" >&2; exit 1; }

pid=""
cleanup() {
    # Test tmux sessions first: their `echoctl attach --follow` would restart a stopped daemon.
    tmux list-panes -a -F '#{session_name}|#{pane_start_command}' 2>/dev/null | grep "$STATE" |
        cut -d'|' -f1 | sort -u | while read -r session; do tmux kill-session -t "=$session"; done
    if [ -n "$pid" ] && ps -o command= -p "$pid" | grep -q "$APP"; then kill "$pid"; fi
    sleep 1
    "$E" shutdown --force >/dev/null 2>&1 || true
    # KEEP_SAMPLES=<folder> keeps the samples, to see where the time went.
    if [ -n "${KEEP_SAMPLES:-}" ]; then mkdir -p "$KEEP_SAMPLES" && cp "$WORK"/*.sample "$KEEP_SAMPLES"/ 2>/dev/null || true; fi
    rm -rf "$STATE" "$WORK"
    defaults delete dev.agenthub.Echo.test filesShown >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

git clone -q "$ROOT" "$REPO"
cd "$REPO"
"$E" ui orchestrator --name one >/dev/null
"$E" ui orchestrator --new-branch bench/two --name two >/dev/null
"$E" ui orchestrator --new-branch bench/three --name three >/dev/null
# A ledger with Workers in it, as the human's has: each row is a view a switch may redraw.
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    "$E" worker start lee --spec "work $n" --title "bench task $n" >/dev/null
done

cp -R "$ROOT/app/build/Echo.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier dev.agenthub.Echo.test" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" 2>/dev/null
# The test copy's own defaults, never the human's Echo's.
if [ -n "${FILES:-}" ]; then defaults write dev.agenthub.Echo.test filesShown -bool true; fi
# In the background: the human keeps the keyboard and the front window.
open -g -n --env HUB_STATE="$STATE" --env HUB_TEST_AGENT="$AGENT" "$APP"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pid=$(pgrep -f "$APP/Contents/MacOS/HubApp" || true)
    [ -n "$pid" ] && break
    sleep 1
done
[ -n "$pid" ] || { echo "the test app did not start" >&2; exit 1; }
sleep 3

# Each agent shown once, so every run switches between kept terminals.
for a in a1 a2 a3; do "$E" ui show "$a"; sleep 1; done

busy() {
    python3 -I - "$1" <<'EOF'
import re, sys
lines = open(sys.argv[1]).read().split('\n')
# The main thread is labelled either way, depending on what ran on it.
start = next(i for i, l in enumerate(lines) if 'Main Thread' in l or 'com.apple.main-thread' in l)
end = next(i for i in range(start + 1, len(lines)) if re.match(r'^\s{4}\d+ Thread_', lines[i]) or lines[i].startswith('Total number'))
total = int(lines[start].split()[0])
idle = sum(int(m.group(1)) for l in lines[start + 1:end] if (m := re.search(r'(\d+) mach_msg2_trap', l)))
print(total - idle)
EOF
}

# Workers starting up redraw the ledger on their own; measure once that has died down, and show
# what the app does in the same time with no switching, which is in every run's number too.
sleep 15
writer=""
if [ -n "${WRITES:-}" ]; then
    "$E" ui show a1
    sleep 2
    (i=0; while [ $i -lt 100 ]; do echo "$i" >"$REPO/bench-writes.txt"; i=$((i + 1)); sleep 0.1; done) &
    writer=$!
fi
sample "$pid" 9 1 -file "$WORK/idle.sample" >/dev/null 2>&1 || true
if [ -n "$writer" ]; then wait "$writer"; fi
echo "idle: $(busy "$WORK/idle.sample") busy ms in the same time, no switching"

results=""
run=1
while [ "$run" -le "$RUNS" ]; do
    (for _ in 1 2 3 4 5 6 7 8 9 10; do
        for a in a1 a2 a3; do "$E" ui show "$a" >/dev/null; sleep 0.3; done
    done) &
    sample "$pid" 9 1 -file "$WORK/run$run.sample" >"$WORK/sample.log" 2>&1 || true
    wait
    if ! grep -q "Call graph" "$WORK/run$run.sample" 2>/dev/null; then
        echo "run $run: sample failed: $(head -c 300 "$WORK/sample.log")" >&2
        run=$((run + 1)); continue
    fi
    n=$(busy "$WORK/run$run.sample")
    echo "run $run: $n busy ms for 30 switches"
    results="$results $n"
    run=$((run + 1))
done
echo "$results" | tr ' ' '\n' | grep . | sort -n | awk '{ v[NR] = $1 } END {
    m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
    printf "median: %d busy ms for 30 switches, %.1f ms a switch\n", m, m / 30 }'
