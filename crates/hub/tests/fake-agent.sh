#!/bin/sh
# A stand-in for `claude` in daemon tests: $1 is the Task spec, and its first word picks a script.
if [ "$1" = "-p" ] && [ "$2" = "/usage" ] && [ -n "$HUB_FAKE_USAGE_FLAKY" ] && [ ! -e "$HUB_FAKE_USAGE_FLAKY" ]; then
  # The first call fails the way the real one sometimes does: a cost summary, no limits.
  touch "$HUB_FAKE_USAGE_FLAKY"
  printf 'Total cost:            $0.0000\nTotal duration (API):  0s\n'
  exit 0
fi
if [ "$1" = "-p" ] && [ "$2" = "/usage" ]; then
  # What `claude -p /usage` prints on a subscription.
  printf 'You are currently using your subscription to power your Claude Code usage\n\n'
  printf 'Current session: 48%% used · resets Oct 17 at 4:50pm (Asia/Saigon)\n'
  printf 'Current week (all models): 9%% used · resets Oct 23 at 11pm (Asia/Saigon)\n'
  printf 'Current week (Fable): 0%% used · resets Oct 23 at 11pm (Asia/Saigon)\n'
  exit 0
fi
echo "· Working… (1s · fake agent)"
# An Orchestrator gets "orchestrator" first; opened with the request "prompt me", it shows a prompt.
if [ "$1" = "orchestrator" ] && [ "$2" = "prompt me" ]; then shift; fi
case "$1" in
  ask*) answer=$(echoctl ask "Which color?") && echoctl done --state done "answer was $answer" ;;
  done*) echoctl done --state done "finished" ;;
  lesson*) echoctl done --state done "finished" --lesson "Run make db before the tests" ;;
  status*) echoctl send --type status "41 of 44 tests passing
details the ledger leaves out" ;;
  exit*) sleep 2; echo "fake agent giving up"; sleep 1; exit 1 ;;
  finish*)
    # A turn that ends at the input box without `echoctl done`, as Haiku sometimes leaves it.
    sleep 1
    printf '\033[2J\033[H⏺ Both databases are dropped.\n✻ Brewed for 18s · done 4:38 PM\n────\n❯ \n────\n  ⏵⏵ auto mode on · ← 2 agents\n' ;;
  monitor*)
    # At the input box while a Monitor it started still runs.
    sleep 1
    printf '\033[2J\033[H⏺ Watching the server.\n✻ Baked for 2s · done 11:45 PM · 1 shell, 1 monitor still running\n────\n❯ \n────\n  ⏵⏵ auto mode on · 1 shell, 1 monitor · ← 2 agents\n' ;;
  request*) echo "first request: $2" ;;
  echo*) while IFS= read -r line; do echo "got: $line"; done ;;
  size*) while IFS= read -r line; do echo "size: $(stty size)"; done ;;
  prompt*)
    printf '────────\nBash command\n rm -rf junk\nDo you want to proceed?\n> 1. Yes\n  2. No\n'
    IFS= read -r line
    printf '\033[2J\033[H'
    case "$line" in
      "") echo "approved" ;;
      *denied*) echo "denied: $line" ;;
    esac ;;
  *) sleep 600 ;;
esac
sleep 600
