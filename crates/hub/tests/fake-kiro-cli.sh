#!/bin/sh
# A stand-in for `kiro-cli` in tests of Kiro's credits (the daemon runs it when HUB_TEST_KIRO names
# it). Its mode is the first line of $KIRO_HOME/mode (the scratch home the daemon gives the child),
# or $HUB_FAKE_KIRO; the default is ok:
#   ok         signed in; the usage reply is the real sample from docs/research/kiro-cli-usage-spike.md
#   fail       signed in; the reply is success:false
#   admin      signed in; the reply is success:true with no data ("managed by admin")
#   hang       signed in; never answers the usage request, and starts a child that sleeps
#   signedout  `whoami` exits 1
# The script writes its pid to $KIRO_HOME/pid, and the mode of each usage request to $KIRO_HOME/calls.
home=${KIRO_HOME:-/nonexistent}
mode=${HUB_FAKE_KIRO:-$(head -n 1 "$home/mode" 2>/dev/null)}
mode=${mode:-ok}

if [ "$1" = whoami ]; then
  if [ "$mode" = signedout ]; then
    echo "Not logged in"
    exit 1
  fi
  echo '{"accountType":"IamIdentityCenter","startUrl":"https://example.awsapps.com/start","region":"us-east-1","email":"someone@example.com"}'
  exit 0
fi

[ "$1" = acp ] || exit 2
[ -d "$home" ] && echo $$ > "$home/pid"

while IFS= read -r line; do
  case "$line" in
    *'"method":"initialize"'*)
      printf '%s\n' '{"jsonrpc":"2.0","method":"_kiro/memory/syncStatus","params":{"state":"notStarted"}}'
      printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true},"authMethods":[{"id":"aws-builder-id","name":"AWS Builder ID"}]}}'
      ;;
    *'_kiro/account/getUsage'*)
      [ -d "$home" ] && echo "$mode" >> "$home/calls"
      case "$mode" in
        hang)
          sleep 300 &
          echo $! > "$home/sleeper"
          wait
          ;;
        fail)
          printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"success":false,"message":"Failed to retrieve usage information: connect ECONNREFUSED 127.0.0.1:9"}}'
          ;;
        admin)
          printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"success":true,"message":"Your plan is managed by admin"}}'
          ;;
        *)
          printf '%s\n' '{"jsonrpc":"2.0","id":7,"result":{"success":false,"message":"a reply for another request"}}'
          printf 'not json at all\n'
          printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"success":true,"message":"Plan: KIRO PRO+ | 1 usage breakdowns","data":{"planName":"KIRO PRO+","billingCycleReset":"2026-12-01","overagesEnabled":false,"isEnterprise":true,"usageBreakdowns":[{"resourceType":"CREDIT","displayName":"Credits","used":603.62,"limit":2000,"percentage":30,"currentOverages":0,"overageRate":0.04,"overageCharges":0,"currency":"USD","hasLimit":true}],"bonusCredits":[],"addOnCredits":[],"overageCapable":true}}}'
          ;;
      esac
      ;;
  esac
done
