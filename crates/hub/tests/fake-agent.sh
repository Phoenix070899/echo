#!/bin/sh
# A stand-in for `claude` in daemon tests: $1 is the Task spec, and its first word picks a script.
# Sign-ins (accounts.rs): Echo's own login is a file in its config folder; the human's is always there.
case "$1 $2" in
  "auth status")
    case "$CLAUDE_CONFIG_DIR" in
      */accounts/claude)
        if [ -e "$CLAUDE_CONFIG_DIR/fake-login" ]; then
          printf '{"loggedIn": true, "authMethod": "claude.ai", "email": "echo@example.com"}\n'
        else
          printf '{"loggedIn": false, "authMethod": "none"}\n'; exit 1
        fi ;;
      *) printf '{"loggedIn": true, "authMethod": "claude.ai", "email": "human@example.com"}\n' ;;
    esac
    exit 0 ;;
  "auth login") touch "$CLAUDE_CONFIG_DIR/fake-login"; echo "Login successful."; exit 0 ;;
  "auth logout") rm -f "$CLAUDE_CONFIG_DIR/fake-login"; echo "Successfully logged out."; exit 0 ;;
  "login status")
    case "$CODEX_HOME" in
      */accounts/codex) [ -e "$CODEX_HOME/fake-login" ] && { echo "Logged in using ChatGPT"; exit 0; }; echo "Not logged in"; exit 1 ;;
      *) echo "Logged in using ChatGPT"; exit 0 ;;
    esac ;;
  "login "|"logout ") [ "$1" = login ] && touch "$CODEX_HOME/fake-login" || rm -f "$CODEX_HOME/fake-login"; exit 0 ;;
  "whoami ") printf 'Logged in with Builder ID\nEmail: human@example.com\n'; exit 0 ;;
  # Model lists (models.rs): Codex's catalog and Kiro's.
  "debug models")
    # As large as the real catalog, more than a pipe holds.
    printf '{"about": "%s", "models": [{"slug": "gpt-test", "display_name": "GPT-Test", "visibility": "list", "priority": 1}]}\n' "$(head -c 300000 /dev/zero | tr '\0' x)"
    exit 0 ;;
  "chat --list-models") printf '{"models": [{"model_name": "claude-haiku-5.5", "model_id": "claude-haiku-5.5"}]}\n'; exit 0 ;;
esac
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
  "Verify the work of"*)
    # What the daemon starts to verify a writer: the verdict follows from the writer's Task and report.
    case "$1" in
      *ALWAYSFAIL*) echoctl done --state done "Verdict: fail
P1 foo.rs:1 broken" ;;
      *"next: "*) echoctl done --state done "Verdict: pass" ;;
      *FAILME*) echoctl done --state done "Verdict: fail
P1 foo.rs:1 broken" ;;
      *NOVERDICT*) echoctl done --state done "looks fine to me" ;;
      *) echoctl done --state done "Verdict: pass" ;;
    esac ;;
  ask*) answer=$(echoctl ask "Which color?") && echoctl done --state done "answer was $answer" ;;
  done*)
    echoctl done --state done "finished"
    # The turn then ends at the input box, as Claude Code's does.
    printf '\033[2J\033[H⏺ Reported.\n✻ Brewed for 3s · done 4:38 PM\n────\n❯ \n────\n  ⏵⏵ auto mode on\n' ;;
  account*) echoctl done --state done "config: ${CLAUDE_CONFIG_DIR:-none} codex: ${CODEX_HOME:-none}" ;;
  next*)
    # Reports, then takes each line typed at its input box as its next Task.
    echoctl done --state done "first Task done"
    while IFS= read -r line; do echoctl done --state done "next: $line"; done ;;
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
  idle*|turns*)
    # Its first turn, then at its input box; "turns" starts a turn for each line typed, "idle" ignores them.
    sleep 2
    printf '\033[2J\033[H⏺ Ready.\n────\n❯ \n────\n'
    while IFS= read -r line; do
      case "$1" in turns*) printf '\033[2J\033[H⏺ %s\n· Thinking… (1s · ↓ 9 tokens)\n────\n❯ \n────\n' "$line" ;; esac
    done ;;
  request*) echo "first request: $2" ;;
  orchestrator)
    [ -n "$2" ] && echo "renewed with: $2"
    if [ -n "$HUB_FAKE_CHAT" ]; then
      # Echo's chat end to end: each line typed is a turn, written to the transcript Echo reads.
      printf '────\n❯ \n────\n'
      n=0
      while IFS= read -r line; do
        n=$((n + 1))
        printf '{"type":"user","uuid":"u%s","message":{"content":"%s"}}\n' "$n" "$line" >>"$HUB_FAKE_CHAT"
        printf '\033[2J\033[H⏺ Bash(sleep 2)\n✶ Thinking… (1s · ↓ 9 tokens)\n────\n❯ \n────\n'
        sleep 2
        printf '{"type":"assistant","uuid":"a%s","message":{"content":[{"type":"text","text":"got: %s"}]}}\n' "$n" "$line" >>"$HUB_FAKE_CHAT"
        printf '\033[2J\033[H⏺ got: %s\n────\n❯ \n────\n' "$line"
      done
    fi
    sleep 600 ;;
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
