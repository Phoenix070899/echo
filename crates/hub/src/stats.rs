//! `echoctl stats`: what Workers and Orchestrators spend their tokens on, read from their Claude Code
//! transcripts.
//! Costs are in input-token equivalents (a cache read 0.1, a write 1.25 for 5 min or 2 for 1 h,
//! output 5), so the shares hold whatever the model's price; dollars use each model's price.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::io::BufRead;
use std::path::{Path, PathBuf};

use serde_json::{json, Value};

/// One Worker session's totals.
#[derive(Default, Debug, PartialEq)]
pub struct Session {
    pub turns: u64,
    /// Context of the first request: what every later turn re-reads before any work.
    pub first_context: u64,
    pub context: u64,
    pub input: u64,
    pub write_5m: u64,
    pub write_1h: u64,
    pub read: u64,
    pub output: u64,
    /// The first request's input and cache writes, in input-token equivalents.
    pub cold_cost: f64,
    pub reads: u64,
    pub shell_reads: u64,
    pub searches: u64,
    /// Read calls that repeat a file and range already read, with no Edit or Write since.
    pub repeat_reads: u64,
    /// What the session cost at each request's model price.
    pub dollars: f64,
    /// The context of the first request after each message typed in after an `echoctl done`:
    /// a follow-up Task, a review, or the human, on top of everything the session already holds.
    pub carried: Vec<u64>,
    /// Times Claude Code compacted the conversation.
    pub compactions: u64,
}

impl Session {
    pub fn cost(&self) -> f64 {
        self.input as f64
            + self.write_5m as f64 * 1.25
            + self.write_1h as f64 * 2.0
            + self.read as f64 * 0.1
            + self.output as f64 * 5.0
    }
}

/// Totals for one transcript. Claude Code writes an assistant message once per content block,
/// each with the same usage, so usage counts once per message id and tools once per tool id.
pub fn session(transcript: impl BufRead) -> Session {
    // (model, usage) per message.
    let mut usage: Vec<(String, Value)> = Vec::new();
    let mut usage_at: HashMap<String, usize> = HashMap::new();
    let mut tools = HashSet::new();
    let mut read_before: HashSet<(String, String)> = HashSet::new();
    let mut s = Session::default();
    // The messages whose context is carried into a follow-up, by index into `usage`.
    let mut carried_at: Vec<usize> = Vec::new();
    let (mut reported, mut followed_up) = (false, false);
    for line in transcript.lines().map_while(Result::ok) {
        let Ok(entry) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        match entry["type"].as_str() {
            Some("assistant") => {}
            Some("user") => {
                if reported && entry["isMeta"] != true && typed(&entry["message"]["content"]) {
                    (reported, followed_up) = (false, true);
                }
                continue;
            }
            Some("system") => {
                s.compactions += (entry["subtype"] == "compact_boundary") as u64;
                continue;
            }
            _ => continue,
        }
        let message = &entry["message"];
        if let (Some(id), Some(u)) = (message["id"].as_str(), message.get("usage")) {
            match usage_at.get(id) {
                Some(&at) => usage[at].1 = u.clone(),
                None => {
                    if std::mem::take(&mut followed_up) {
                        carried_at.push(usage.len());
                    }
                    usage_at.insert(id.to_string(), usage.len());
                    let model = message["model"].as_str().unwrap_or("").to_string();
                    usage.push((model, u.clone()));
                }
            }
        }
        for block in message["content"].as_array().into_iter().flatten() {
            if block["type"] != "tool_use" || !tools.insert(block["id"].as_str().unwrap_or("").to_string()) {
                continue;
            }
            let input = &block["input"];
            if command_key(block["name"].as_str().unwrap_or(""), input) == "done" {
                reported = true;
            }
            match block["name"].as_str().unwrap_or("") {
                "Read" => {
                    s.reads += 1;
                    let file = input["file_path"].as_str().unwrap_or("").to_string();
                    let range = format!("{}:{}", input["offset"], input["limit"]);
                    if !read_before.insert((file, range)) {
                        s.repeat_reads += 1;
                    }
                }
                "Edit" | "Write" => {
                    let file = input["file_path"].as_str().unwrap_or("");
                    read_before.retain(|(f, _)| f != file);
                }
                "Grep" | "Glob" => s.searches += 1,
                "Bash" => match input["command"].as_str().unwrap_or("").split_whitespace().next() {
                    Some("cat" | "head" | "tail" | "sed" | "nl" | "less") => s.shell_reads += 1,
                    Some("grep" | "rg" | "find" | "fd" | "ls" | "graft") => s.searches += 1,
                    _ => {}
                },
                _ => {}
            }
        }
    }
    for (at, (model, u)) in usage.iter().enumerate() {
        let n = |key: &str| u[key].as_u64().unwrap_or(0);
        let (w5, w1) = match u.get("cache_creation") {
            Some(c) => (
                c["ephemeral_5m_input_tokens"].as_u64().unwrap_or(0),
                c["ephemeral_1h_input_tokens"].as_u64().unwrap_or(0),
            ),
            None => (n("cache_creation_input_tokens"), 0),
        };
        let context = n("input_tokens") + n("cache_read_input_tokens") + n("cache_creation_input_tokens");
        if at == 0 {
            s.first_context = context;
            s.cold_cost = n("input_tokens") as f64 + w5 as f64 * 1.25 + w1 as f64 * 2.0;
        }
        if carried_at.contains(&at) {
            s.carried.push(context);
        }
        s.dollars += dollars(
            model,
            context,
            n("input_tokens"),
            w5,
            w1,
            n("cache_read_input_tokens"),
            n("output_tokens"),
        );
        s.turns += 1;
        s.context += context;
        s.input += n("input_tokens");
        s.write_5m += w5;
        s.write_1h += w1;
        s.read += n("cache_read_input_tokens");
        s.output += n("output_tokens");
    }
    s
}

/// Whether a user entry is text typed or pasted in, not a tool result or Claude Code's own note.
fn typed(content: &Value) -> bool {
    let human = |text: &str| {
        ![
            "<local-command",
            "<command-",
            "<system-reminder>",
            "[Request interrupted",
        ]
        .iter()
        .any(|note| text.trim_start().starts_with(note))
    };
    match content {
        Value::String(text) => human(text),
        Value::Array(blocks) => blocks
            .iter()
            .any(|b| b["type"] == "text" && human(b["text"].as_str().unwrap_or(""))),
        _ => false,
    }
}

/// Dollars per million tokens for a request of `context` tokens to `model`: (input, cache read,
/// output). A cache write is 1.25 times input for 5 min and 2 times for 1 h. Anthropic's list
/// prices for the 5.5 models (Fable 5.1), checked 2026-11-11, stand for their whole family; Haiku
/// costs five times as much past 100k tokens. Another model, or `<synthetic>`, costs nothing.
fn prices(model: &str, context: u64) -> (f64, f64, f64) {
    if model.contains("opus") {
        (4.0, 0.20, 20.0)
    } else if model.contains("sonnet") {
        (2.0, 0.20, 10.0)
    } else if model.contains("haiku") && context > 100_000 {
        (0.50, 0.05, 2.50)
    } else if model.contains("haiku") {
        (0.10, 0.01, 0.50)
    } else if model.contains("fable") {
        (10.0, 0.25, 50.0)
    } else {
        (0.0, 0.0, 0.0)
    }
}

fn dollars(model: &str, context: u64, input: u64, write_5m: u64, write_1h: u64, read: u64, output: u64) -> f64 {
    let (per_input, per_read, per_output) = prices(model, context);
    (input as f64 * per_input
        + write_5m as f64 * per_input * 1.25
        + write_1h as f64 * per_input * 2.0
        + read as f64 * per_read
        + output as f64 * per_output)
        / 1_000_000.0
}

/// Claude Code's transcripts folder.
pub fn projects_dir() -> PathBuf {
    std::env::var_os("CLAUDE_CONFIG_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".claude"))
        .join("projects")
}

/// The transcript of `session_id`, in whichever project folder Claude Code put it.
pub fn transcript(projects: &Path, session_id: &str) -> Option<PathBuf> {
    std::fs::read_dir(projects)
        .ok()?
        .flatten()
        .map(|dir| dir.path().join(format!("{session_id}.jsonl")))
        .find(|path| path.exists())
}

/// How many requests an agent's session has made, and the context of its last one.
pub fn session_context(session_id: &str) -> Option<(usize, u64)> {
    session_context_in(&projects_dir(), session_id)
}

fn session_context_in(projects: &Path, session_id: &str) -> Option<(usize, u64)> {
    let path = transcript(projects, session_id)?;
    let file = std::fs::File::open(path).ok()?;
    let session = agent_session(std::io::BufReader::new(file), 0.0);
    Some((session.requests.len(), session.requests.last()?.context))
}

fn median(mut values: Vec<u64>) -> u64 {
    values.sort_unstable();
    values.get(values.len() / 2).copied().unwrap_or(0)
}

/// The report for Workers given as (profile, Claude session id).
pub fn report(workers: &[(String, String)]) -> Value {
    let projects = projects_dir();
    let mut by_profile: HashMap<&str, Vec<Session>> = HashMap::new();
    for (profile, session_id) in workers {
        let Some(path) = transcript(&projects, session_id) else {
            continue;
        };
        let Ok(file) = std::fs::File::open(path) else { continue };
        let s = session(std::io::BufReader::new(file));
        if s.turns > 0 {
            by_profile.entry(profile).or_default().push(s);
        }
    }
    let all: Vec<&Session> = by_profile.values().flatten().collect();
    let total: f64 = all.iter().map(|s| s.cost()).sum::<f64>().max(1.0);
    let share = |part: f64| (part / total * 100.0).round();
    let sum = |f: fn(&Session) -> u64| all.iter().map(|s| f(s)).sum::<u64>();
    let per_worker = |n: u64| {
        if all.is_empty() {
            0.0
        } else {
            (n as f64 / all.len() as f64 * 10.0).round() / 10.0
        }
    };
    let mut profiles: Vec<Value> = by_profile
        .iter()
        .map(|(profile, list)| {
            let turns: u64 = list.iter().map(|s| s.turns).sum();
            let cost: f64 = list.iter().map(|s| s.cost()).sum();
            json!({
                "profile": profile,
                "workers": list.len(),
                "dollars": list.iter().map(|s| s.dollars).sum::<f64>().round(),
                "turnsPerWorker": turns / list.len() as u64,
                "startContext": median(list.iter().map(|s| s.first_context).collect()),
                "contextPerTurn": list.iter().map(|s| s.context).sum::<u64>() / turns.max(1),
                "share": share(cost),
            })
        })
        .collect();
    profiles.sort_by(|a, b| b["share"].as_f64().partial_cmp(&a["share"].as_f64()).unwrap());
    let turns = sum(|s| s.turns);
    let reads = sum(|s| s.reads);
    let carried: Vec<u64> = all.iter().flat_map(|s| s.carried.iter().copied()).collect();
    json!({
        "workers": workers.len(),
        "withTranscript": all.len(),
        "turns": turns,
        "dollars": all.iter().map(|s| s.dollars).sum::<f64>().round(),
        "followUps": { "count": carried.len(), "carriedContext": median(carried) },
        "compactions": sum(|s| s.compactions),
        "startContext": median(all.iter().map(|s| s.first_context).collect()),
        "contextPerTurn": sum(|s| s.context) / turns.max(1),
        "share": {
            "cacheReads": share(sum(|s| s.read) as f64 * 0.1),
            "cacheWrites": share(sum(|s| s.write_5m) as f64 * 1.25 + sum(|s| s.write_1h) as f64 * 2.0),
            "output": share(sum(|s| s.output) as f64 * 5.0),
            "coldStarts": share(all.iter().map(|s| s.cold_cost).sum()),
        },
        "perWorker": {
            "reads": per_worker(reads),
            "shellReads": per_worker(sum(|s| s.shell_reads)),
            "searches": per_worker(sum(|s| s.searches)),
        },
        "repeatReads": if reads == 0 { 0.0 } else { (sum(|s| s.repeat_reads) as f64 / reads as f64 * 100.0).round() },
        "profiles": profiles,
    })
}

/// One request an Orchestrator sent to the model.
#[derive(Debug, PartialEq)]
pub struct Request {
    /// When it was sent and when its answer was complete, in Unix seconds.
    pub sent: f64,
    pub done: f64,
    /// Seconds since the previous request's answer; 0 for the first.
    pub gap: f64,
    pub context: u64,
    pub input: u64,
    pub write_5m: u64,
    pub write_1h: u64,
    pub read: u64,
    pub output: u64,
    /// What it cost at its model's price.
    pub dollars: f64,
    /// What woke it: the command or tool whose result arrived last ("wait", "worker list", "Read"),
    /// "notification" for a background task's, "empty wait" for a listener that returned nothing,
    /// "human" for a typed message, "start" for the session's first request.
    pub after: String,
}

impl Request {
    pub fn cost(&self) -> f64 {
        self.input as f64
            + self.write_5m as f64 * 1.25
            + self.write_1h as f64 * 2.0
            + self.read as f64 * 0.1
            + self.output as f64 * 5.0
    }

    /// Almost nothing of a large context came from the cache, so all of it was written again.
    /// The first request of a session is always cold and is not counted as such.
    pub fn cold(&self) -> bool {
        self.after != "start" && self.context > COLD_CONTEXT && self.read * 10 < self.context
    }
}

/// A context under this many tokens is too small for a cold request to matter.
const COLD_CONTEXT: u64 = 20_000;

/// One Orchestrator session: its requests from `since` on, and what its tool results weighed.
#[derive(Default, Debug)]
pub struct AgentSession {
    pub model: String,
    pub requests: Vec<Request>,
    /// Tool results by command: (calls, bytes).
    pub results: BTreeMap<String, (u64, u64)>,
}

/// A transcript's timestamp ("2026-11-11T12:51:16.174Z", always UTC) as Unix seconds.
pub fn unix_seconds(stamp: &str) -> Option<f64> {
    let (date, time) = stamp.trim_end_matches('Z').split_once('T')?;
    let mut parts = date.split('-').map(|p| p.parse::<i64>().ok());
    let (year, month, day) = (parts.next()??, parts.next()??, parts.next()??);
    let mut clock = time.split(':').map(|p| p.parse::<f64>().ok());
    let (hour, minute, second) = (clock.next()??, clock.next()??, clock.next()??);
    // Days since 1970-01-01: the civil-from-days algorithm run backwards.
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let day_of_year = (153 * (month + if month > 2 { -3 } else { 9 }) + 2) / 5 + day - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    let days = era * 146_097 + day_of_era - 719_468;
    Some(days as f64 * 86_400.0 + hour * 3600.0 + minute * 60.0 + second)
}

/// What a tool call is called in the report: the `echoctl` command a Bash call runs ("wait",
/// "worker list"), the background-output readers together, else the tool's own name.
fn command_key(tool: &str, input: &Value) -> String {
    match tool {
        "Bash" => {
            let command = input["command"].as_str().unwrap_or("");
            let mut words = command.split_whitespace();
            if !words.any(|w| w.rsplit('/').next() == Some("echoctl")) {
                return "Bash".into();
            }
            let sub: Vec<&str> = words
                .take_while(|w| !w.starts_with(['&', '|', ';', '>', '<']))
                .map(|w| w.trim_end_matches([';', '&', '|']))
                .filter(|w| !w.is_empty() && !w.starts_with('-'))
                .take(2)
                .collect();
            match sub.as_slice() {
                [] => "echoctl".into(),
                ["worker", second, ..] => format!("worker {second}"),
                [first, ..] => first.to_string(),
            }
        }
        "BashOutput" | "TaskOutput" => "background output".into(),
        other => other.into(),
    }
}

/// The text of a tool result, whether it is a string or a list of blocks.
fn result_text(content: &Value) -> String {
    match content {
        Value::String(text) => text.clone(),
        Value::Array(blocks) => blocks
            .iter()
            .filter_map(|b| b["text"].as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        _ => String::new(),
    }
}

/// What `echoctl wait` prints when its time ran out with no message.
const EMPTY_WAIT: &str = "No messages in ";

/// An Orchestrator's requests and tool results from its transcript. `since` (Unix seconds) drops
/// what came earlier; it still keeps the gap before the first request it counts. Entries of
/// sub-agents (`isSidechain`) are not the Orchestrator's own context and are skipped.
pub fn agent_session(transcript: impl BufRead, since: f64) -> AgentSession {
    let mut s = AgentSession::default();
    let mut at: HashMap<String, usize> = HashMap::new();
    let mut tools: HashMap<String, String> = HashMap::new();
    let mut counted: Vec<(String, u64)> = Vec::new();
    let mut woke_at = 0.0;
    let mut woken_by = String::from("human");
    for line in transcript.lines().map_while(Result::ok) {
        let Ok(entry) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        if entry["isSidechain"] == true {
            continue;
        }
        let stamp = entry["timestamp"].as_str().and_then(unix_seconds);
        let message = &entry["message"];
        match entry["type"].as_str() {
            Some("assistant") => {
                for block in message["content"].as_array().into_iter().flatten() {
                    if block["type"] == "tool_use" {
                        if let (Some(id), Some(name)) = (block["id"].as_str(), block["name"].as_str()) {
                            tools.insert(id.to_string(), command_key(name, &block["input"]));
                        }
                    }
                }
                let (Some(id), Some(u)) = (message["id"].as_str(), message.get("usage")) else {
                    continue;
                };
                if message["model"] == "<synthetic>" {
                    continue;
                }
                let done = stamp.unwrap_or(woke_at);
                let n = |key: &str| u[key].as_u64().unwrap_or(0);
                let (write_5m, write_1h) = match u.get("cache_creation") {
                    Some(c) => (
                        c["ephemeral_5m_input_tokens"].as_u64().unwrap_or(0),
                        c["ephemeral_1h_input_tokens"].as_u64().unwrap_or(0),
                    ),
                    None => (n("cache_creation_input_tokens"), 0),
                };
                let context = n("input_tokens") + n("cache_read_input_tokens") + n("cache_creation_input_tokens");
                let model = message["model"].as_str().unwrap_or("");
                let request = Request {
                    sent: if woke_at > 0.0 { woke_at.min(done) } else { done },
                    done,
                    gap: 0.0,
                    context,
                    input: n("input_tokens"),
                    write_5m,
                    write_1h,
                    read: n("cache_read_input_tokens"),
                    output: n("output_tokens"),
                    dollars: dollars(
                        model,
                        context,
                        n("input_tokens"),
                        write_5m,
                        write_1h,
                        n("cache_read_input_tokens"),
                        n("output_tokens"),
                    ),
                    after: if s.requests.is_empty() {
                        "start".into()
                    } else {
                        std::mem::replace(&mut woken_by, "chain".into())
                    },
                };
                // One message arrives as one entry per content block, each with the same usage.
                match at.get(id) {
                    Some(&i) => {
                        let (sent, after) = (s.requests[i].sent, std::mem::take(&mut s.requests[i].after));
                        s.requests[i] = Request { sent, after, ..request };
                    }
                    None => {
                        at.insert(id.to_string(), s.requests.len());
                        s.requests.push(request);
                    }
                }
                if let Some(model) = message["model"].as_str() {
                    s.model = model.to_string();
                }
            }
            Some("user") => {
                let counts = stamp.is_none_or(|t| t >= since);
                let mut result_cause = None;
                let mut text_cause = None;
                let mut texts: Vec<String> = Vec::new();
                match &message["content"] {
                    Value::String(text) => texts.push(text.clone()),
                    Value::Array(blocks) => {
                        for block in blocks {
                            match block["type"].as_str() {
                                Some("tool_result") => {
                                    let key = block["tool_use_id"]
                                        .as_str()
                                        .and_then(|id| tools.get(id))
                                        .cloned()
                                        .unwrap_or_else(|| "other tool".into());
                                    let text = result_text(&block["content"]);
                                    if counts {
                                        counted.push((key.clone(), text.len() as u64));
                                    }
                                    let listener = matches!(key.as_str(), "wait" | "background output" | "other tool");
                                    result_cause = Some(if listener && text.contains(EMPTY_WAIT) {
                                        "empty wait".to_string()
                                    } else {
                                        key
                                    });
                                }
                                Some("text") => texts.extend(block["text"].as_str().map(str::to_string)),
                                _ => {}
                            }
                        }
                    }
                    _ => {}
                }
                for text in &texts {
                    if text.contains("<task-notification>") {
                        if counts {
                            counted.push(("notification".into(), text.len() as u64));
                        }
                        text_cause = Some(if text.contains(EMPTY_WAIT) {
                            "empty wait"
                        } else {
                            "notification"
                        });
                    } else if text_cause.is_none() {
                        text_cause = Some("human");
                    }
                }
                if let Some(cause) = result_cause.or(text_cause.map(str::to_string)) {
                    woken_by = cause;
                }
                if let Some(t) = stamp {
                    woke_at = t;
                }
            }
            _ => {
                if let Some(t) = stamp {
                    woke_at = t;
                }
            }
        }
    }
    for (key, bytes) in counted {
        let entry = s.results.entry(key).or_default();
        entry.0 += 1;
        entry.1 += bytes;
    }
    let mut done = 0.0;
    for r in &mut s.requests {
        r.gap = if done > 0.0 { (r.sent - done).max(0.0) } else { 0.0 };
        done = r.done;
    }
    s.requests.retain(|r| r.sent >= since);
    s
}

/// Which cache lifetime the writes used.
fn lifetime(write_5m: u64, write_1h: u64) -> &'static str {
    match (write_5m, write_1h) {
        (0, 0) => "none",
        (_, 0) => "5m",
        (0, _) => "1h",
        _ => "mixed",
    }
}

fn percent(part: f64, total: f64) -> f64 {
    // An empty sum is -0.0; adding 0.0 keeps it from printing as "-0%".
    (part / total.max(1.0) * 100.0).round() + 0.0
}

/// The report for Orchestrators given as (agent id, repo, name, Claude session id), over the
/// requests sent from `since` (Unix seconds) on.
pub fn orchestrators(agents: &[(i64, String, Option<String>, String)], since: i64) -> Value {
    orchestrators_in(&projects_dir(), agents, since)
}

/// The same, with Claude Code's transcripts folder given.
fn orchestrators_in(projects: &Path, agents: &[(i64, String, Option<String>, String)], since: i64) -> Value {
    let mut sessions: Vec<(&(i64, String, Option<String>, String), AgentSession)> = Vec::new();
    for agent in agents {
        let Some(path) = transcript(projects, &agent.3) else {
            continue;
        };
        let Ok(file) = std::fs::File::open(path) else { continue };
        let s = agent_session(std::io::BufReader::new(file), since as f64);
        if !s.requests.is_empty() {
            sessions.push((agent, s));
        }
    }
    let all: Vec<&Request> = sessions.iter().flat_map(|(_, s)| s.requests.iter()).collect();
    let total: f64 = all.iter().map(|r| r.cost()).sum();
    let sum = |f: fn(&Request) -> u64| all.iter().map(|r| f(r)).sum::<u64>();
    let cold: Vec<&Request> = all.iter().copied().filter(|r| r.cold()).collect();
    let gaps = |from: f64, to: f64| cold.iter().filter(|r| r.gap >= from && r.gap < to).count();

    // What woke each request, with how many of those were cold and what they cost.
    let mut wakes: HashMap<&str, (u64, u64, f64)> = HashMap::new();
    for r in &all {
        let w = wakes.entry(&r.after).or_default();
        w.0 += 1;
        w.1 += r.cold() as u64;
        w.2 += r.cost();
    }
    let mut wakes: Vec<Value> = wakes
        .into_iter()
        .map(|(after, (requests, cold, cost))| {
            json!({ "after": after, "requests": requests, "cold": cold, "share": percent(cost, total) })
        })
        .collect();
    wakes.sort_by(|a, b| b["share"].as_f64().partial_cmp(&a["share"].as_f64()).unwrap());

    let mut results: BTreeMap<&str, (u64, u64)> = BTreeMap::new();
    for (_, s) in &sessions {
        for (command, (calls, bytes)) in &s.results {
            let r = results.entry(command).or_default();
            r.0 += calls;
            r.1 += bytes;
        }
    }
    let mut results: Vec<Value> = results
        .into_iter()
        .map(|(command, (calls, bytes))| json!({ "command": command, "calls": calls, "bytes": bytes }))
        .collect();
    results.sort_by(|a, b| b["bytes"].as_u64().cmp(&a["bytes"].as_u64()));

    let per_session: Vec<Value> = sessions
        .iter()
        .map(|((id, repo, name, _), s)| {
            let contexts: Vec<u64> = s.requests.iter().map(|r| r.context).collect();
            let cold: Vec<&Request> = s.requests.iter().filter(|r| r.cold()).collect();
            let cost: f64 = s.requests.iter().map(|r| r.cost()).sum();
            json!({
                "agent": format!("a{id}"),
                "repo": repo,
                "name": name,
                "model": s.model,
                "requests": s.requests.len(),
                "dollars": s.requests.iter().map(|r| r.dollars).sum::<f64>().round(),
                "context": {
                    "first": s.requests[0].context,
                    "median": median(contexts),
                    "last": s.requests[s.requests.len() - 1].context,
                },
                "cacheWrite": lifetime(
                    s.requests.iter().map(|r| r.write_5m).sum(),
                    s.requests.iter().map(|r| r.write_1h).sum(),
                ),
                "cold": cold.len(),
                "coldShare": percent(cold.iter().map(|r| r.cost()).sum(), cost),
                "coldGaps": cold.iter().map(|r| r.gap.round() as u64).collect::<Vec<_>>(),
            })
        })
        .collect();

    let firsts: Vec<u64> = sessions.iter().map(|(_, s)| s.requests[0].context).collect();
    let lasts: Vec<u64> = sessions
        .iter()
        .map(|(_, s)| s.requests[s.requests.len() - 1].context)
        .collect();
    json!({
        "agents": agents.len(),
        "withTranscript": sessions.len(),
        "requests": all.len(),
        "dollars": all.iter().map(|r| r.dollars).sum::<f64>().round(),
        "context": {
            "first": median(firsts),
            "median": median(all.iter().map(|r| r.context).collect()),
            "last": median(lasts),
        },
        "cacheWrite": lifetime(sum(|r| r.write_5m), sum(|r| r.write_1h)),
        "share": {
            "cacheReads": percent(sum(|r| r.read) as f64 * 0.1, total),
            "cacheWrites": percent(sum(|r| r.write_5m) as f64 * 1.25 + sum(|r| r.write_1h) as f64 * 2.0, total),
            "output": percent(sum(|r| r.output) as f64 * 5.0, total),
            "coldRequests": percent(cold.iter().map(|r| r.cost()).sum(), total),
        },
        "cold": {
            "requests": cold.len(),
            "ofRequests": percent(cold.len() as f64, all.len() as f64),
            "gaps": {
                "under5m": gaps(0.0, 300.0),
                "from5mTo1h": gaps(300.0, 3600.0),
                "over1h": gaps(3600.0, f64::INFINITY),
            },
            "afterEmptyWait": cold.iter().filter(|r| r.after == "empty wait").count(),
        },
        "wakes": wakes,
        "toolResults": results,
        "sessions": per_session,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assistant(id: &str, usage: Value, tools: Value) -> String {
        json!({ "type": "assistant", "message": { "id": id, "usage": usage, "content": tools } }).to_string()
    }

    #[test]
    fn counts_usage_once_per_message_and_tools_once_per_call() {
        let first = json!({ "input_tokens": 10, "cache_read_input_tokens": 0, "cache_creation_input_tokens": 1000,
                            "cache_creation": { "ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 1000 },
                            "output_tokens": 20 });
        let second = json!({ "input_tokens": 5, "cache_read_input_tokens": 1000, "cache_creation_input_tokens": 50,
                             "output_tokens": 30 });
        let read = |id: &str, file: &str| json!({ "type": "tool_use", "id": id, "name": "Read", "input": { "file_path": file } });
        let lines = [
            assistant("m1", first.clone(), json!([read("t1", "/a.rs")])),
            // The same message again, for its next content block.
            assistant("m1", first, json!([read("t1", "/a.rs"), read("t2", "/a.rs")])),
            assistant(
                "m2",
                second,
                json!([
                    { "type": "tool_use", "id": "t3", "name": "Bash", "input": { "command": "sed -n 1,9p b.rs" } },
                    { "type": "tool_use", "id": "t4", "name": "Bash", "input": { "command": "rg needle" } },
                    { "type": "tool_use", "id": "t5", "name": "Edit", "input": { "file_path": "/a.rs" } },
                    read("t6", "/a.rs"),
                ]),
            ),
            "not json".to_string(),
        ]
        .join("\n");
        let s = session(lines.as_bytes());
        assert_eq!(s.turns, 2);
        assert_eq!(s.first_context, 1010);
        assert_eq!(s.context, 1010 + 1055);
        assert_eq!((s.write_1h, s.write_5m, s.read, s.output), (1000, 50, 1000, 50));
        assert_eq!(s.cold_cost, 10.0 + 2000.0);
        assert_eq!(
            (s.reads, s.repeat_reads),
            (3, 1),
            "a read after an edit is not a repeat"
        );
        assert_eq!((s.shell_reads, s.searches), (1, 1));
    }

    #[test]
    fn a_follow_up_after_a_final_report_counts_the_context_it_carries_in() {
        let usage = |read: u64| json!({ "input_tokens": 0, "cache_read_input_tokens": read, "output_tokens": 0 });
        let turn = |id: &str, read: u64, tools: Value| {
            json!({ "type": "assistant", "message": { "id": id, "model": "claude-sonnet-5-5", "usage": usage(read), "content": tools } })
                .to_string()
        };
        let user = |content: Value| json!({ "type": "user", "message": { "content": content } }).to_string();
        let lines = [
            user(json!("Fix the parser")),
            turn("m1", 50_000, json!([])),
            // Typed in before any Final Report: not a follow-up.
            user(json!("also check the tests")),
            turn("m2", 60_000, json!([call("t1", "echoctl done --state done; echo ok")])),
            user(json!([{ "type": "tool_result", "tool_use_id": "t1", "content": "sent" }])),
            turn("m3", 61_000, json!([])),
            json!({ "type": "user", "isMeta": true, "message": { "content": "Caveat" } }).to_string(),
            json!({ "type": "system", "subtype": "compact_boundary" }).to_string(),
            user(json!([{ "type": "text", "text": "Sasuke found a bug: fix it" }])),
            turn("m4", 90_000, json!([])),
            turn("m5", 91_000, json!([])),
        ]
        .join("\n");
        let s = session(lines.as_bytes());
        assert_eq!(s.carried, [90_000]);
        assert_eq!(s.compactions, 1);
        // 352k cache reads at Sonnet's $0.20 per million.
        assert!((s.dollars - 0.0704).abs() < 1e-9, "{}", s.dollars);
    }

    #[test]
    fn a_request_costs_its_models_list_price() {
        assert_eq!(dollars("claude-opus-5-5", 0, 1_000_000, 0, 0, 0, 0), 4.0);
        assert_eq!(
            dollars("claude-sonnet-5-5", 0, 0, 1_000_000, 1_000_000, 0, 1_000_000),
            2.5 + 4.0 + 10.0
        );
        assert_eq!(dollars("claude-haiku-5-5", 50_000, 0, 0, 0, 0, 1_000_000), 0.5);
        assert_eq!(dollars("claude-haiku-5-5", 150_000, 0, 0, 0, 0, 1_000_000), 2.5);
        assert_eq!(dollars("<synthetic>", 0, 1_000_000, 0, 0, 0, 0), 0.0);
    }

    /// One Orchestrator transcript line. `at` is seconds after 10:00:00 UTC on 2026-11-11.
    fn entry(at: u32, kind: &str, message: Value) -> Value {
        let (h, m, s) = (10 + at / 3600, at / 60 % 60, at % 60);
        json!({ "type": kind, "timestamp": format!("2026-11-11T{h:02}:{m:02}:{s:02}.000Z"), "message": message })
    }

    fn model_turn(at: u32, id: &str, read: u64, written_1h: u64, tools: Value) -> Value {
        let usage = json!({ "input_tokens": 10, "cache_read_input_tokens": read,
                            "cache_creation_input_tokens": written_1h, "output_tokens": 40,
                            "cache_creation": { "ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": written_1h } });
        entry(
            at,
            "assistant",
            json!({ "id": id, "model": "claude-opus-5-5", "usage": usage, "content": tools }),
        )
    }

    fn call(id: &str, command: &str) -> Value {
        json!({ "type": "tool_use", "id": id, "name": "Bash", "input": { "command": command } })
    }

    fn result(at: u32, id: &str, text: &str) -> Value {
        entry(
            at,
            "user",
            json!({ "content": [{ "type": "tool_result", "tool_use_id": id, "content": text }] }),
        )
    }

    /// An hour of an Orchestrator's life: a listener that comes back empty at its 3600 s timeout
    /// and wakes the Orchestrator cold, then a `worker list`.
    fn orchestrator_transcript() -> String {
        let empty_wait =
            "<task-notification>No messages in 3600s. Run the backstop, then wait again.</task-notification>";
        let sub_agent = json!({ "type": "assistant", "isSidechain": true, "timestamp": "2026-11-11T11:00:20.000Z",
            "message": { "id": "side", "usage": { "input_tokens": 999999 }, "content": [] } });
        let lines = [
            entry(0, "user", json!({ "content": "build the thing" })),
            model_turn(
                5,
                "m1",
                0,
                30_000,
                json!([call("t1", "cd /r && echoctl worker list --json")]),
            ),
            result(6, "t1", &"x".repeat(4000)),
            model_turn(10, "m2", 30_010, 200, json!([call("t2", "echoctl wait")])),
            result(11, "t2", "running in the background"),
            model_turn(15, "m3", 30_210, 0, json!([])),
            entry(
                3616,
                "user",
                json!({ "content": [{ "type": "text", "text": empty_wait }] }),
            ),
            model_turn(3625, "m4", 0, 30_500, json!([call("t3", "echoctl worker list")])),
            sub_agent,
            // The same message again, for its next content block.
            model_turn(3626, "m4", 0, 30_500, json!([call("t3", "echoctl worker list")])),
            result(3627, "t3", &"y".repeat(3000)),
            model_turn(3630, "m5", 30_510, 0, json!([])),
        ];
        lines.iter().map(|l| l.to_string()).collect::<Vec<_>>().join("\n") + "\nnot json"
    }

    #[test]
    fn an_orchestrators_cold_wake_after_an_empty_wait_is_counted_with_its_gap() {
        let s = agent_session(orchestrator_transcript().as_bytes(), 0.0);
        let after: Vec<&str> = s.requests.iter().map(|r| r.after.as_str()).collect();
        assert_eq!(after, ["start", "worker list", "wait", "empty wait", "worker list"]);
        assert_eq!(
            s.requests.iter().map(|r| r.context).collect::<Vec<_>>(),
            [30_010, 30_220, 30_220, 30_510, 30_520]
        );
        assert_eq!(
            s.requests.iter().map(|r| r.cold()).collect::<Vec<_>>(),
            [false, false, false, true, false],
            "the first request is not cold, a warm one is not, the one after an hour is"
        );
        // Sent when the notification arrived (3616 s), after the previous answer finished (15 s).
        assert_eq!(s.requests[3].gap, 3601.0);
        assert_eq!(s.model, "claude-opus-5-5");
        assert_eq!(s.results["worker list"], (2, 7000));
        assert_eq!(s.results["wait"], (1, 25));
        assert_eq!(s.results["notification"].0, 1);
        assert!(!s.results.contains_key("other tool"));
    }

    #[test]
    fn a_sessions_size_is_its_request_count_and_the_context_of_the_last_one() {
        let dir = std::env::temp_dir().join(format!("echoctl-context-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("-repo")).unwrap();
        std::fs::write(dir.join("-repo/sid-1.jsonl"), orchestrator_transcript()).unwrap();
        assert_eq!(session_context_in(&dir, "sid-1"), Some((5, 30_520)));
        assert_eq!(session_context_in(&dir, "sid-none"), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn an_orchestrators_window_drops_earlier_requests_but_keeps_the_gap_before_the_first() {
        let since = unix_seconds("2026-11-11T11:00:00.000Z").unwrap();
        let s = agent_session(orchestrator_transcript().as_bytes(), since);
        assert_eq!(
            s.requests.iter().map(|r| r.after.as_str()).collect::<Vec<_>>(),
            ["empty wait", "worker list"]
        );
        assert_eq!(s.requests[0].gap, 3601.0);
        assert_eq!(
            s.results["worker list"],
            (1, 3000),
            "the result before the window is not counted"
        );
        assert!(!s.results.contains_key("wait"));
    }

    #[test]
    fn the_orchestrator_report_gathers_sessions_cold_requests_and_tool_results() {
        let dir = std::env::temp_dir().join(format!("echoctl-stats-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("-repo")).unwrap();
        std::fs::write(dir.join("-repo/sess-1.jsonl"), orchestrator_transcript()).unwrap();
        let agents = vec![
            (3, "/r".to_string(), Some("Rerank".to_string()), "sess-1".to_string()),
            (4, "/r".to_string(), None, "no-transcript".to_string()),
        ];
        let r = orchestrators_in(&dir, &agents, 0);
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(
            (
                r["agents"].as_u64(),
                r["withTranscript"].as_u64(),
                r["requests"].as_u64()
            ),
            (Some(2), Some(1), Some(5))
        );
        assert_eq!(r["cacheWrite"], "1h");
        assert_eq!(
            r["context"],
            json!({ "first": 30_010, "median": 30_220, "last": 30_520 })
        );
        assert_eq!(r["cold"]["requests"], 1);
        assert_eq!(r["cold"]["gaps"], json!({ "under5m": 0, "from5mTo1h": 0, "over1h": 1 }));
        assert_eq!(r["cold"]["afterEmptyWait"], 1);
        assert_eq!(r["toolResults"][0]["command"], "worker list");
        assert_eq!(r["toolResults"][0]["bytes"], 7000);
        assert_eq!(r["sessions"][0]["agent"], "a3");
        assert_eq!(r["sessions"][0]["coldGaps"], json!([3601]));
        let cold_wake = r["wakes"]
            .as_array()
            .unwrap()
            .iter()
            .find(|w| w["after"] == "empty wait")
            .unwrap();
        assert_eq!(
            (cold_wake["requests"].as_u64(), cold_wake["cold"].as_u64()),
            (Some(1), Some(1))
        );
        // No transcripts at all is a report of zeros, not an error.
        assert_eq!(orchestrators_in(&dir, &agents, 0)["requests"], 0);
    }

    #[test]
    fn timestamps_become_unix_seconds() {
        assert_eq!(unix_seconds("1970-01-01T00:00:00Z"), Some(0.0));
        assert_eq!(unix_seconds("2024-02-29T00:00:00.000Z"), Some(1_709_164_800.0));
        assert_eq!(unix_seconds("2026-11-11T12:51:16.174Z"), Some(1_794_401_476.174));
        assert_eq!(unix_seconds("yesterday"), None);
    }

    #[test]
    fn a_tool_call_is_named_by_the_echoctl_command_it_runs() {
        let bash = |command: &str| command_key("Bash", &json!({ "command": command }));
        assert_eq!(bash("cd /r && echoctl worker read w3 --lines 40"), "worker read");
        assert_eq!(bash("/usr/local/bin/echoctl wait --timeout 30"), "wait");
        assert_eq!(bash("echoctl status --json | jq ."), "status");
        assert_eq!(bash("echoctl worker list; echoctl wait"), "worker list");
        assert_eq!(bash("echoctl done --state done; echo ok"), "done");
        assert_eq!(bash("echoctl"), "echoctl");
        assert_eq!(bash("git status"), "Bash");
        assert_eq!(command_key("BashOutput", &json!({})), "background output");
        assert_eq!(command_key("Read", &json!({})), "Read");
    }
}
