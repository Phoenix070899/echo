Verdict: ACP

# Kiro credits without a session (spike T03)

Plan: `docs/plans/2026-11-13-kiro-parity/` (T03, feeds T04). Run on 2026-11-13 with `kiro-cli 3.3.0` (Mach-O, bundled server `@kiro/agent` 3.3.0), signed in through IAM Identity Center, plan `KIRO PRO+`. All runs: no chat session, no prompt, no `session/new`. Email, start URL and profile ARN are redacted below; credit numbers are the real ones.

## Answer

`kiro-cli acp --agent-engine v3 --auth-method cli` answers the ACP extension request `_kiro/account/getUsage` over stdio, with no session, in about 1.7 s from spawn (initialize reply at 0.5 to 0.8 s, usage reply 0.85 s after the request). It returns the credits used, the plan limit and the billing-cycle reset date. Five runs in a row returned the same reading and spent nothing. The per-session sum (fallback) works too and is recorded for completeness, but T04 should build the ACP call.

## 1. ACP: what was run

Driver: a short Python script under `/tmp/kirousage` (removed at the end) that spawns the child in its own process group, writes JSON-RPC lines to its stdin, reads lines from its stdout, kills the group on exit, and has a 60 s watchdog.

```
argv:   kiro-cli acp --agent-engine v3 --auth-method cli
cwd:    any (a scratch folder was used)
stdin:  one JSON object per line (newline-delimited JSON-RPC 2.0, as ACP over stdio)
```

Request 1 (id 1), sent at once:
```
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{},"clientInfo":{"name":"echo-usage-spike","version":"0"}}}
```
Reply (0.5 to 0.8 s later; `extensionMethods` shortened to its first entries, the real list has 43):
```
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":true,"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"sessionCapabilities":{"list":{},"close":{},"delete":{},"fork":{"_meta":{"kiro":{"messageId":true}}}},"_meta":{"kiro":{"checkpoints":true,"sessionList":true,"policyNotifications":true,"extensionMethods":["_kiro/knowledge","_kiro/memory/list", "..."],"sessionSources":["local","remote"],"executionTargets":["local","cloud-sandbox"],"logging":{"logDir":"<KIRO_HOME>/logs/20261113T124524305-63225","channels":[{"name":"kiro","filePath":"..."},{"name":"mcp","filePath":"..."},{"name":"powers","filePath":"..."}]}}}},"authMethods":[{"id":"aws-builder-id","name":"AWS Builder ID"},{"id":"aws-iam-identity-center","name":"AWS IAM Identity Center"}]}}
```
`_kiro/account/getUsage` is not in that `extensionMethods` list, but the server handles it (found in `acp-server.js`, below). Do not gate on the list.

Request 2 (id 2), sent after the reply to id 1:
```
{"jsonrpc":"2.0","id":2,"method":"_kiro/account/getUsage","params":{}}
```
Notifications can arrive in between (no `id`), for example `{"jsonrpc":"2.0","method":"_kiro/memory/syncStatus","params":{"state":"notStarted"}}`. A reader must skip any line whose `id` is not 2.

Reply (0.85 s after the request), the real sample:
```
{"jsonrpc":"2.0","id":2,"result":{"success":true,"message":"Plan: KIRO PRO+ | 1 usage breakdowns","data":{"planName":"KIRO PRO+","billingCycleReset":"2026-12-01","overagesEnabled":false,"isEnterprise":true,"usageBreakdowns":[{"resourceType":"CREDIT","displayName":"Credits","used":603.62,"limit":2000,"percentage":30,"currentOverages":0,"overageRate":0.04,"overageCharges":0,"currency":"USD","hasLimit":true}],"bonusCredits":[],"addOnCredits":[],"overageCapable":true}}}
```

Failure sample (child started with `HTTPS_PROXY=http://127.0.0.1:9` so the service call could not connect; the child still answers, in 0.1 s):
```
{"jsonrpc":"2.0","id":2,"result":{"success":false,"message":"Failed to retrieve usage information: connect ECONNREFUSED 127.0.0.1:9"}}
```

Third shape, from the bundled source (`handleGetUsage`, not reproduced because it needs an account the service refuses): when the service answers AccessDenied with reason FEATURE_NOT_SUPPORTED the reply is
```
{"jsonrpc":"2.0","id":2,"result":{"success":true,"message":"Your plan is managed by admin"}}
```
with no `data`. T04 treats a missing `data` the same as `success:false`: no reading, nothing shown, last good value kept. A not-signed-in child was not reproduced (it would need a fresh HOME and a download of the 390 MB server bundle under `~/Library/Application Support/kiro-cli/kas`); the source wraps a failed token lookup into the same `success:false` reply with a message, so the `success` flag is the only thing to test.

### Where the method comes from
- `kiro-cli acp --help` lists the flags used (`--agent-engine`, `--auth-method` with default `cli` meaning "use the kiro-cli login session"). `acp` is a hidden subcommand: it is missing from `kiro-cli --help` and `--help-all`.
- The method name is not in the Mach-O binary's strings; it is in the bundled server `~/Library/Application Support/kiro-cli/kas/3.3.0-<hash>/node_modules/@kiro/agent/dist/server/acp-server.js` (read-only grep). Handler: `"_kiro/account/getUsage": e => this.handleGetUsage(e)`; it ignores its parameter. The server classifies it as `localOnly` and persistence `transient` (no session record). `handleGetUsage` calls the service operation `GetUsageLimits` with the login's bearer token and reshapes the answer (`transformUsageLimits`).
- The kiro.dev pages for the CLI and ACP (`https://kiro.dev/docs/cli/acp/`, `https://kiro.dev/docs/cli/`) do not mention `_kiro/account/getUsage`. The method is undocumented and may change; T04 must treat any parse failure as "no reading".

### Response fields (from the sample and `transformUsageLimits`)
| field | type | meaning |
|---|---|---|
| `result.success` | bool | false on any failure |
| `result.message` | string | human text, not for parsing |
| `data.planName` | string | `"KIRO PRO+"`, or `"Unknown"` |
| `data.billingCycleReset` | string `YYYY-MM-DD` (UTC date) or `"Unknown"` | next reset; equals `/usage`'s "resets on 2026-12-01" |
| `data.usageBreakdowns[]` | array | one entry per resource; credits is the one with `resourceType: "CREDIT"` |
| `.used`, `.limit` | numbers, credits, fractional (`603.62`) | used this cycle and plan allowance (the TUI shows "340.98 of 2000" the same way) |
| `.percentage` | integer | `floor(used / limit * 100)`, 0 when `limit` is 0 (here 30; exact is 30.18) |
| `.hasLimit` | bool | false when `limit` is not a real cap |
| `.currentOverages`, `.overageRate`, `.overageCharges`, `.currency` | numbers, string | overage data (`0`, `0.04`, `0`, `"USD"`) |
| `data.overagesEnabled`, `data.overageCapable` | bool | |
| `data.isEnterprise` | bool | true here (IAM Identity Center is treated as admin-managed billing) |
| `data.bonusCredits[]` | array, empty here | per source: `{name, used, total, daysUntilExpiry}` |
| `data.addOnCredits[]` | array, empty here | per source: `{used, total, expiresAt, isActive}` |

Units: credits are plan credits, floats; percent is a plain integer 0 to 100 (floored) or compute it from `used`/`limit`; the reset is an ISO calendar date with no time or zone (UTC date).

Read-after-write caveat: the figure is the service's, and it lagged behind the TUI during this session (the human's own Kiro was working; the reading stayed 603.62 across five calls over several minutes). Echo's own per-turn `Credits:` lines are not a substitute for it.

### Side effects (checked)
- No session: no `session/new` or prompt was sent. The listing of `~/.kiro` (everything except `logs/` and files inside session folders) was identical before and after a run with the default `KIRO_HOME`, including `sessions/*/*/` (48 session folders both times), `session-index/`, `session-leases/`.
- No credits: `used` was 603.62 before and after repeated calls (5 runs).
- One thing it does write: a log folder `<KIRO_HOME>/logs/<timestamp>-<pid>/` with `kiro.log`, `mcp.log`, `powers.log` per run, and the CLI keeps only about the newest 11 log folders. A call every 5 minutes would push the human's own older logs out of `~/.kiro/logs`. Running the child with `KIRO_HOME=<scratch dir>` avoids that: it worked (same reading) because the login lives in `~/Library/Application Support/kiro-cli/data.sqlite3`, not under `KIRO_HOME`; the scratch dir received only `logs/`, `sessions/` (empty) and `settings/cli.json`. Verified for IAM Identity Center; not for other login types.
- Process: the child exits by itself 0.1 s after its stdin is closed (exit 0). With a kill of its process group (SIGTERM, then SIGKILL) it exits 143. No grandchildren were left (`pgrep -f 'kiro-cli acp'` empty after every run).

### Timings (this machine, 5 runs, wall clock from spawn)
- initialize reply: 0.54 to 0.83 s.
- usage reply: 1.66 s from spawn in the two runs whose timestamps were printed (about 0.85 s after the request); failure (refused connection): 0.94 s.
- whole call: about 1.7 s plus the 0.1 s stdin-close exit (my driver's 2.4 to 3.0 s totals include a deliberate 1 s sleep between SIGTERM and SIGKILL, and 2.7 s on the default-`KIRO_HOME` run).

## 2. Other subcommands

`kiro-cli --help-all` lists the same commands as `--help` (agent, chat, login, logout, whoami, profile, settings, diagnostic, issue, crew, mcp, powers, update, integrations, serve). Nothing prints credits: `whoami` and `profile` are login only (see `kiro-cli-spike.md` Q11). `kiro-cli serve --port <PORT>` (default 8082) starts a persistent WebSocket server for the v3 engine; it was not started (it would leave a listener, and ACP over stdio already answers). Not needed.

## 3. Fallback: sum of per-turn credits (verdict would have been SUM)

Method: stream every `~/.kiro/sessions/*/sess_*/messages.jsonl` line by line (never the whole file); the agent name is `session_start.payload.agentType`; add `usage_summary.payload.promptTurnSummaries[0].usage` for entries whose `timestamp` (UTC ISO) is on or after the billing-period start (reset date minus one month, here 2026-11-01; the calendar month is the same here because the reset is on the 1st).

Measured here (2026-11-13, warm file cache, Python, one pass): 37 `messages.jsonl` files, 85,488,739 bytes (the biggest, the human's current session, 84,798,604 bytes), 3,337 lines (longest line 4.4 MB), **0.04 to 0.10 s**. A Rust reader with a per-line prefilter on `"type":"usage_summary"` would be similar. Cold cache was not measured.

Result since 2026-11-01:
| origin (`agentType`) | turns | credits |
|---|---|---|
| starts with `echo-` (Echo's agents and the spikes' `echo-spike-*`) | 58 | 0.7235 |
| other (the human's own agents, `vibe`, `default-v2`) | 29 | 533.9894 |
| no `session_start` found | 2 | 0.0168 |

`usage_summary.status` counts in that window: success 82, aborted 7, failed 4. The sum over all origins (about 534.7) is 89 % of the account's 603.62, so a sum misses usage from other machines, deleted sessions and anything not logged; Echo's share alone is 0.72 of 2000 (0.04 %). That share is small and not what the human wants on the bar; the account figure is.

## What T04 should build

Verdict ACP. In its own thread on the usage 5-minute cadence (never blocking `events`):

1. Skip rule, cheap: `kiro-cli` must resolve on PATH, and `kiro-cli whoami` must exit 0 (about 1.0 s, no network error shown; cache the answer for the cadence). Signed in: stdout (`--format json`) is
   ```
   {"accountType":"IamIdentityCenter","startUrl":"https://<redacted>.awsapps.com/start","region":"us-east-1","email":"<redacted>"}

   Profile:
   KiroProfile-us-east-1
   arn:aws:<redacted>
   ```
   exit 0. Signed out (checked with a throwaway `HOME`): `kiro-cli whoami --format json` prints `{"account":null}`, plain `kiro-cli whoami` prints `Not logged in`, both exit 1. Use the exit status only; do not parse the email. Do not read `data.sqlite3` (it holds tokens). The ACP reply itself is also safe without this check (`success:false`), so a failure of either step means "show nothing, keep the last good value".
2. Spawn `kiro-cli acp --agent-engine v3 --auth-method cli` with piped stdin and stdout, stderr to null, in its own process group, with `KIRO_HOME` pointing at a scratch dir under Echo's state folder (keeps `~/.kiro/logs` clean; fall back to the default if the dir cannot be made), and a 60 s hard timeout.
3. Write the `initialize` line above, read lines until `id == 1` arrives, write the `getUsage` line, read lines until `id == 2` arrives, skipping lines without that id.
4. Close stdin, wait up to 2 s for exit, then kill the process group (SIGTERM, then SIGKILL). The child must never survive the call, on success, error or timeout.
5. Parse `result`: require `success == true` and a `data` object; take the `usageBreakdowns` entry with `resourceType == "CREDIT"`; `used` and `limit` are f64; percent = `round(used / limit * 100)` when `limit > 0` (or use the server's floored `percentage`: say which in the code, 30 vs 30.18 here); `billingCycleReset` is `YYYY-MM-DD` (show as the plan's example, `Dec 1`); `"Unknown"` or a missing field means no reset text. The example entry from the plan becomes `{"name":"Kiro credits","percent":30,"resets":"Dec 1","detail":"603.62 of 2000"}` (round `used` for display as the TUI does: 603.62, 340.98).
6. Tolerance: unknown fields are ignored, `data` absent, `success:false`, a non-JSON line, a missing breakdown, `limit == 0` or `hasLimit == false` all mean "no reading".

Parse-test samples for T04: the three `id:2` replies above (success, failure, plan managed by admin) and the `whoami` outputs. The fake `kiro-cli` stand-in for tests should print the `initialize` reply and then the `id:2` reply for whichever it is told to, reading stdin lines and exiting when stdin closes.

## Cleanup

Scratch `/tmp/kirousage` (driver, raw replies, a copy of the binary's strings, a fake `HOME`, a scratch `KIRO_HOME`) removed. No file was added to, changed or deleted under `~/.kiro` by hand; the only writes there were the CLI's own log folders from the default-`KIRO_HOME` runs (above). No chat session started. The human's own `kiro-cli` TUI processes (a `kiro-cli`, a `bun` and a `node` under `~/Library/Application Support/kiro-cli`) were running before and were not touched.
