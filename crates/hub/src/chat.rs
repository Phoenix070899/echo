//! An agent's conversation as chat items, read from its Claude Code transcript (ADR 0010).

use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use serde_json::{json, Value};

/// Most lines a tool's output keeps; the terminal has the rest.
const OUTPUT_LINES: usize = 40;
/// Most characters any one text keeps, so a pasted log does not swell a reply.
pub(crate) const TEXT_CHARS: usize = 20_000;

/// The chat items of one transcript line, in order.
///
/// - `user`: what the human (or Echo for them) typed.
/// - `reply`: the agent's text.
/// - `tool`: one tool call, by its `tool_use` id.
/// - `result`: the output of the tool call `id`, which arrives on a later line.
/// - `event`: a background note, such as a task notification or a command's output.
/// - `divider`: the context was compacted.
pub fn items(line: &str) -> Vec<Value> {
    let Ok(entry) = serde_json::from_str::<Value>(line) else {
        return vec![];
    };
    // Subagents' own turns and Claude Code's injected context are not the conversation.
    if entry["isSidechain"] == true || entry["isMeta"] == true {
        return vec![];
    }
    let at = entry["timestamp"].clone();
    let uuid = entry["uuid"].as_str().unwrap_or("").to_string();
    match entry["type"].as_str() {
        Some("user") if entry["isCompactSummary"] == true => {
            vec![json!({ "kind": "divider", "id": uuid, "text": "Context compacted", "at": at })]
        }
        Some("user") => match &entry["message"]["content"] {
            Value::String(text) => typed(text, &uuid, &at).into_iter().collect(),
            Value::Array(blocks) => blocks
                .iter()
                .enumerate()
                .filter_map(|(n, block)| match block["type"].as_str() {
                    Some("tool_result") => Some(json!({
                        "kind": "result",
                        "id": block["tool_use_id"],
                        "text": output(&block["content"]),
                        "error": block["is_error"] == true,
                    })),
                    Some("text") => typed(block["text"].as_str().unwrap_or(""), &format!("{uuid}.{n}"), &at),
                    _ => None,
                })
                .collect(),
            _ => vec![],
        },
        Some("assistant") => entry["message"]["content"]
            .as_array()
            .into_iter()
            .flatten()
            .enumerate()
            .filter_map(|(n, block)| match block["type"].as_str() {
                Some("text") => {
                    let text = block["text"].as_str().unwrap_or("").trim();
                    (!text.is_empty()).then(|| {
                        json!({ "kind": "reply", "id": format!("{uuid}.{n}"), "text": cut(text, TEXT_CHARS), "at": at })
                    })
                }
                Some("tool_use") => Some(tool(block, &at)),
                _ => None,
            })
            .collect(),
        Some("system") if entry["subtype"] == "compact_boundary" => {
            vec![json!({ "kind": "divider", "id": uuid, "text": "Context compacted", "at": at })]
        }
        _ => vec![],
    }
}

/// A user line's text: the human's message, a slash command, or a background event.
fn typed(text: &str, id: &str, at: &Value) -> Option<Value> {
    let text = text.trim();
    if text.is_empty() || text.starts_with("<system-reminder>") {
        return None;
    }
    if let Some(name) = tag(text, "command-name") {
        let args = tag(text, "command-args").unwrap_or_default();
        let command = format!("{name} {args}").trim().to_string();
        return Some(json!({ "kind": "user", "id": id, "text": command, "at": at }));
    }
    if text.starts_with("<local-command-stdout>") || text.starts_with("<local-command-stderr>") {
        let body = tag(text, "local-command-stdout").or_else(|| tag(text, "local-command-stderr"))?;
        return (!body.trim().is_empty())
            .then(|| json!({ "kind": "event", "id": id, "text": cut(body.trim(), TEXT_CHARS), "at": at }));
    }
    if text.starts_with('<') {
        // A task notification or another tagged note: its summary, else its text without tags.
        let inner = tag(text, "summary").unwrap_or_else(|| untagged(text));
        return Some(json!({ "kind": "event", "id": id, "text": cut(inner.trim(), TEXT_CHARS), "at": at }));
    }
    Some(json!({ "kind": "user", "id": id, "text": cut(text, TEXT_CHARS), "at": at }))
}

fn tag(text: &str, name: &str) -> Option<String> {
    let open = format!("<{name}>");
    let start = text.find(&open)? + open.len();
    let end = text[start..].find(&format!("</{name}>"))? + start;
    Some(text[start..end].to_string())
}

/// `text` without its `<tag>`s, and without the ids and paths tags alone hold.
fn untagged(text: &str) -> String {
    let mut out = String::new();
    let mut rest = text;
    while let Some(open) = rest.find('<') {
        out.push_str(&rest[..open]);
        let Some(close) = rest[open..].find('>') else { break };
        let name = &rest[open + 1..open + close];
        rest = &rest[open + close + 1..];
        // Skip the body of a tag that only carries plumbing.
        if ["task-id", "tool-use-id", "output-file", "status"].contains(&name) {
            if let Some(end) = rest.find(&format!("</{name}>")) {
                rest = &rest[end + name.len() + 3..];
            }
        }
    }
    out.push_str(rest);
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// A tool call, with what its folded row shows (`summary`) and what it shows expanded.
fn tool(block: &Value, at: &Value) -> Value {
    let name = block["name"].as_str().unwrap_or("Tool");
    let input = &block["input"];
    let field = |key: &str| input[key].as_str().unwrap_or("");
    let summary = match name {
        "Bash" => first_line(field("command")),
        "Read" | "Write" | "Edit" | "NotebookEdit" => field("file_path").to_string(),
        "Grep" | "Glob" => field("pattern").to_string(),
        "Agent" | "Task" => field("description").to_string(),
        "WebFetch" => field("url").to_string(),
        "WebSearch" => field("query").to_string(),
        "Skill" => field("skill").to_string(),
        _ => input
            .as_object()
            .and_then(|o| o.values().find_map(Value::as_str))
            .map(first_line)
            .unwrap_or_default(),
    };
    let mut item = json!({ "kind": "tool", "id": block["id"], "tool": name, "summary": cut(&summary, 300), "at": at });
    match name {
        "Bash" => item["detail"] = json!(cut(field("command"), TEXT_CHARS)),
        "Edit" => {
            item["old"] = json!(cut(field("old_string"), TEXT_CHARS));
            item["new"] = json!(cut(field("new_string"), TEXT_CHARS));
        }
        "Write" => item["new"] = json!(cut(field("content"), TEXT_CHARS)),
        "Agent" | "Task" => item["detail"] = json!(cut(field("prompt"), TEXT_CHARS)),
        _ => {}
    }
    item
}

/// A tool result's text: a string, or a list of text blocks; at most `OUTPUT_LINES` lines.
pub(crate) fn output(content: &Value) -> String {
    let text = match content {
        Value::String(text) => text.clone(),
        Value::Array(blocks) => blocks
            .iter()
            .filter_map(|b| b["text"].as_str())
            .collect::<Vec<_>>()
            .join("\n"),
        _ => String::new(),
    };
    let lines: Vec<&str> = text.lines().collect();
    let mut kept = lines[..lines.len().min(OUTPUT_LINES)].join("\n");
    if lines.len() > OUTPUT_LINES {
        kept.push_str(&format!("\n… {} more lines", lines.len() - OUTPUT_LINES));
    }
    cut(&kept, TEXT_CHARS)
}

pub(crate) fn first_line(text: &str) -> String {
    text.lines()
        .find(|l| !l.trim().is_empty())
        .unwrap_or("")
        .trim()
        .to_string()
}

pub(crate) fn cut(text: &str, chars: usize) -> String {
    match text.char_indices().nth(chars) {
        Some((at, _)) => format!("{}…", &text[..at]),
        None => text.to_string(),
    }
}

/// Marks who typed each `user` item, from the texts recorded as typed in (origin, text): `from`
/// is `orchestrator` or `human`, and Echo's own notes become events. A text nobody recorded was
/// typed in the terminal, by the human.
pub fn mark_origins(items: &mut [Value], inputs: &[(String, String)]) {
    let squash = |text: &str| text.split_whitespace().collect::<Vec<_>>().join(" ");
    let known: Vec<(&str, String)> = inputs
        .iter()
        .map(|(origin, text)| (origin.as_str(), squash(text)))
        .collect();
    for item in items.iter_mut().filter(|item| item["kind"] == "user") {
        let text = squash(item["text"].as_str().unwrap_or(""));
        // A long text is cut in the item, so its start is what matches.
        let text = text.trim_end_matches('…');
        let Some((origin, _)) = known
            .iter()
            .find(|(_, typed)| typed == text || (text.len() > 200 && typed.starts_with(text)))
        else {
            continue;
        };
        if *origin == "echo" {
            item["kind"] = json!("event");
        } else {
            item["from"] = json!(origin);
        }
    }
}

/// A read of a transcript: its items, the offset of the first whole line they came from (where
/// an older page ends), and the offset after the last (where the next read continues).
pub struct Page {
    pub items: Vec<Value>,
    pub start: u64,
    pub end: u64,
}

/// Every item after byte `after`; else up to `limit` items ending at byte `before` (the file's end
/// when not given). Only whole lines count, so a line being written waits for the next read.
pub fn read(path: &Path, limit: usize, after: Option<u64>, before: Option<u64>) -> std::io::Result<Page> {
    read_with(path, limit, after, before, || |_, line: &str| items(line))
}

/// `read` for a transcript whose lines `fresh` makes a parser for: one per range read, so a parser
/// may remember what it saw on the lines before (a Kiro turn's error), never across two reads. The
/// parser is given each line's byte offset, to look at the file before it where memory is not enough.
pub(crate) fn read_with<P: FnMut(u64, &str) -> Vec<Value>>(
    path: &Path,
    limit: usize,
    after: Option<u64>,
    before: Option<u64>,
    fresh: impl Fn() -> P,
) -> std::io::Result<Page> {
    let mut file = std::fs::File::open(path)?;
    let size = file.metadata()?.len();
    if let Some(after) = after.filter(|&a| a <= size) {
        let (items, end) = parse_range(&mut file, after, size, fresh())?;
        return Ok(Page {
            items: items.into_iter().map(|(_, item)| item).collect(),
            start: after,
            end,
        });
    }
    let stop = before.unwrap_or(size).min(size);
    // Back from `stop`, reading further back until `limit` items fit or the file starts.
    let mut window: u64 = 2 << 20;
    loop {
        let from = stop.saturating_sub(window);
        let (mut items, end) = parse_range(&mut file, from, stop, fresh())?;
        if items.len() >= limit || from == 0 {
            items.drain(..items.len().saturating_sub(limit));
            let start = items.first().map_or(from, |(at, _)| *at);
            return Ok(Page {
                items: items.into_iter().map(|(_, item)| item).collect(),
                start,
                end,
            });
        }
        window *= 4;
    }
}

/// The items of every whole line between `start` and `stop`, each with its line's offset, skipping
/// a line cut by `start`; and the offset after the last whole line.
fn parse_range(
    file: &mut std::fs::File,
    start: u64,
    stop: u64,
    mut parse: impl FnMut(u64, &str) -> Vec<Value>,
) -> std::io::Result<(Vec<(u64, Value)>, u64)> {
    file.seek(SeekFrom::Start(start))?;
    let mut bytes = Vec::new();
    (&mut *file).take(stop.saturating_sub(start)).read_to_end(&mut bytes)?;
    let mut from = 0;
    if start > 0 {
        file.seek(SeekFrom::Start(start - 1))?;
        let mut before = [0u8];
        file.read_exact(&mut before)?;
        if before[0] != b'\n' {
            from = bytes.iter().position(|&b| b == b'\n').map_or(bytes.len(), |n| n + 1);
        }
    }
    let whole = bytes.iter().rposition(|&b| b == b'\n').map_or(0, |n| n + 1).max(from);
    let mut out = Vec::new();
    let mut at = from;
    for line in bytes[from..whole].split(|&b| b == b'\n') {
        let offset = start + at as u64;
        at += line.len() + 1;
        for mut item in parse(offset, &String::from_utf8_lossy(line)) {
            // A line without a uuid is named by where it sits, so ids stay unique.
            let id = item["id"].as_str().unwrap_or("").to_string();
            if id.is_empty() || id.starts_with('.') {
                item["id"] = json!(format!("@{offset}{id}"));
            }
            out.push((offset, item));
        }
    }
    Ok((out, start + whole as u64))
}

/// The divider between an earlier session and the next, at the end of the earlier one's page.
pub fn renewed(session: &str) -> Value {
    json!({ "kind": "divider", "id": format!("renewed {session}"), "text": "Session renewed, context cleared" })
}

/// Claude Code's own slash commands the chat offers, with whether each opens a menu the chat
/// cannot draw (it shows in the terminal). `/clear` and `/resume` are left out: they move the
/// agent to another session, which its chat would not follow.
const BUILT_IN: [(&str, &str, bool); 16] = [
    ("compact", "Compact the conversation, keeping a summary", false),
    ("context", "Show how full the context is", false),
    ("cost", "Show this session's cost and duration", false),
    ("usage", "Show plan usage limits", false),
    ("review", "Review a pull request", false),
    ("init", "Write a CLAUDE.md for this repo", false),
    ("add-dir", "Add a working directory", false),
    ("model", "Pick the model", true),
    ("config", "Open the settings", true),
    ("permissions", "Allow and deny tools", true),
    ("agents", "Manage subagents", true),
    ("mcp", "Manage MCP servers", true),
    ("memory", "Edit memory files", true),
    ("hooks", "Manage hooks", true),
    ("status", "Show version, model and account", true),
    ("help", "Show help", true),
];

/// The slash commands the chat completes: Claude Code's own, the skills its transcript lists,
/// and the command files in `dirs` (`~/.claude/commands`, the repo's `.claude/commands`).
pub fn commands(transcript: Option<&Path>, dirs: &[std::path::PathBuf]) -> Vec<Value> {
    let mut out: Vec<Value> = BUILT_IN
        .iter()
        .map(|(name, about, menu)| json!({ "name": name, "description": about, "menu": menu }))
        .collect();
    let mut seen: std::collections::HashSet<String> = BUILT_IN.iter().map(|(name, ..)| name.to_string()).collect();
    let mut add = |name: String, about: String, out: &mut Vec<Value>| {
        if !name.is_empty() && seen.insert(name.clone()) {
            out.push(json!({ "name": name, "description": cut(&about, 160), "menu": false }));
        }
    };
    // The newest skill listing in the transcript: "- name: description" lines.
    if let Some(text) = transcript.and_then(|path| std::fs::read_to_string(path).ok()) {
        let listing = text
            .lines()
            .filter(|line| line.contains("\"skill_listing\""))
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
            .filter_map(|entry| entry["attachment"]["content"].as_str().map(String::from))
            .last();
        for line in listing.iter().flat_map(|listing| listing.lines()) {
            if let Some((name, about)) = line.strip_prefix("- ").and_then(|rest| rest.split_once(": ")) {
                add(name.trim().to_string(), about.trim().to_string(), &mut out);
            }
        }
    }
    for dir in dirs {
        let Ok(entries) = std::fs::read_dir(dir) else { continue };
        let mut files: Vec<_> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|x| x == "md"))
            .collect();
        files.sort();
        for file in files {
            let name = file
                .file_stem()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_default();
            let text = std::fs::read_to_string(&file).unwrap_or_default();
            let about = text
                .lines()
                .find_map(|line| line.strip_prefix("description:"))
                .map(|d| d.trim().trim_matches('"').to_string())
                .unwrap_or_default();
            add(name, about, &mut out);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line(value: Value) -> String {
        value.to_string()
    }

    #[test]
    fn a_human_message_and_a_reply_are_chat() {
        let user = line(json!({ "type": "user", "uuid": "u1", "message": { "content": "fix the build" } }));
        assert_eq!(items(&user)[0]["kind"], "user");
        assert_eq!(items(&user)[0]["text"], "fix the build");
        let reply = line(json!({ "type": "assistant", "uuid": "a1", "message": { "content": [
            { "type": "thinking", "thinking": "hmm" },
            { "type": "text", "text": "Done: the build passes." },
        ] } }));
        let got = items(&reply);
        assert_eq!(got.len(), 1, "thinking is not shown: {got:?}");
        assert_eq!(got[0]["kind"], "reply");
    }

    #[test]
    fn a_tool_call_and_its_result_share_an_id() {
        let call = line(json!({ "type": "assistant", "uuid": "a1", "message": { "content": [
            { "type": "tool_use", "id": "t1", "name": "Bash", "input": { "command": "cargo test\n--quiet" } },
        ] } }));
        let tool = &items(&call)[0];
        assert_eq!(
            (tool["kind"].as_str(), tool["summary"].as_str()),
            (Some("tool"), Some("cargo test"))
        );
        let long = (1..=50).map(|n| n.to_string()).collect::<Vec<_>>().join("\n");
        let result = line(json!({ "type": "user", "uuid": "u2", "message": { "content": [
            { "type": "tool_result", "tool_use_id": "t1", "content": [{ "type": "text", "text": long }] },
        ] } }));
        let result = &items(&result)[0];
        assert_eq!(result["id"], "t1");
        assert!(
            result["text"].as_str().unwrap().ends_with("… 10 more lines"),
            "{result}"
        );
    }

    #[test]
    fn injected_context_and_subagents_are_not_chat() {
        for entry in [
            json!({ "type": "user", "isMeta": true, "message": { "content": "Caveat: ..." } }),
            json!({ "type": "assistant", "isSidechain": true, "message": { "content": [{ "type": "text", "text": "x" }] } }),
            json!({ "type": "user", "message": { "content": "<system-reminder>be brief</system-reminder>" } }),
            json!({ "type": "attachment" }),
        ] {
            assert!(items(&line(entry.clone())).is_empty(), "{entry}");
        }
    }

    #[test]
    fn slash_commands_notifications_and_compaction_read_plainly() {
        let command = line(json!({ "type": "user", "message": { "content":
            "<command-name>/model</command-name>\n<command-message>model</command-message>\n<command-args>opus</command-args>" } }));
        assert_eq!(items(&command)[0]["text"], "/model opus");
        let note = line(json!({ "type": "user", "message": { "content":
            "<task-notification>w12 sent its Final Report</task-notification>" } }));
        assert_eq!(
            (items(&note)[0]["kind"].as_str(), items(&note)[0]["text"].as_str()),
            (Some("event"), Some("w12 sent its Final Report"))
        );
        let task = line(json!({ "type": "user", "message": { "content":
            "<task-notification>\n<task-id>b3</task-id>\n<status>completed</status>\n<summary>Background command \"wait\" completed</summary>\n</task-notification>" } }));
        assert_eq!(items(&task)[0]["text"], "Background command \"wait\" completed");
        let bare = line(json!({ "type": "user", "message": { "content":
            "<task-notification><task-id>b3</task-id><status>failed</status> it stopped</task-notification>" } }));
        assert_eq!(items(&bare)[0]["text"], "it stopped");
        let compact = line(json!({ "type": "system", "subtype": "compact_boundary" }));
        assert_eq!(items(&compact)[0]["kind"], "divider");
    }

    #[test]
    fn commands_are_claude_codes_the_listed_skills_and_command_files() {
        let dir = std::env::temp_dir().join(format!("hub-cmds-{}", std::process::id()));
        std::fs::create_dir_all(dir.join("commands")).unwrap();
        std::fs::write(
            dir.join("commands/ship.md"),
            "---\ndescription: Ship the branch\n---\nDo it",
        )
        .unwrap();
        let listing = json!({ "type": "attachment", "attachment": { "type": "skill_listing",
            "content": "- graft: Find code fast\n- mattpocock-skills:tdd: Test first" } });
        std::fs::write(dir.join("t.jsonl"), line(listing) + "\n").unwrap();
        let got = commands(Some(&dir.join("t.jsonl")), &[dir.join("commands")]);
        let find = |name: &str| got.iter().find(|c| c["name"] == name).cloned();
        assert_eq!(find("model").unwrap()["menu"], true);
        assert!(
            find("clear").is_none(),
            "it moves the agent to a session its chat would not follow"
        );
        assert_eq!(find("mattpocock-skills:tdd").unwrap()["description"], "Test first");
        assert_eq!(find("ship").unwrap()["description"], "Ship the branch");
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn typed_texts_say_who_typed_them() {
        let mut got = vec![
            json!({ "kind": "user", "text": "Fix the  login\nbug" }),
            json!({ "kind": "user", "text": "also add a test" }),
            json!({ "kind": "user", "text": "Your terminal was restarted." }),
            json!({ "kind": "reply", "text": "Fix the login bug" }),
        ];
        let inputs = [
            ("orchestrator".to_string(), "Fix the login bug".to_string()),
            ("echo".to_string(), "Your terminal was restarted.".to_string()),
        ];
        mark_origins(&mut got, &inputs);
        assert_eq!(got[0]["from"], "orchestrator");
        assert!(got[1].get("from").is_none(), "typed in the terminal: the human's");
        assert_eq!(got[2]["kind"], "event");
        assert!(got[3].get("from").is_none());
    }

    #[test]
    fn reading_takes_the_tail_then_only_new_whole_lines() {
        let dir = std::env::temp_dir().join(format!("hub-chat-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("s.jsonl");
        let say = |n: usize| {
            line(json!({ "type": "user", "uuid": format!("u{n}"), "message": { "content": format!("m{n}") } }))
        };
        let text: String = (0..10).map(|n| say(n) + "\n").collect();
        std::fs::write(&path, &text).unwrap();
        let texts = |page: &Page| {
            page.items
                .iter()
                .map(|i| i["text"].as_str().unwrap().to_string())
                .collect::<Vec<_>>()
        };
        let tail = read(&path, 3, None, None).unwrap();
        assert_eq!(texts(&tail), ["m7", "m8", "m9"]);
        assert_eq!(tail.end, text.len() as u64);
        // Older pages end where the last began, back to the file's start.
        let older = read(&path, 5, None, Some(tail.start)).unwrap();
        assert_eq!(texts(&older), ["m2", "m3", "m4", "m5", "m6"]);
        let oldest = read(&path, 5, None, Some(older.start)).unwrap();
        assert_eq!(
            (texts(&oldest), oldest.start),
            (vec!["m0".to_string(), "m1".to_string()], 0)
        );
        // A line still being written is left for the next read.
        let half = say(10);
        std::fs::write(&path, format!("{text}{}", &half[..10])).unwrap();
        assert!(read(&path, 3, Some(tail.end), None).unwrap().items.is_empty());
        std::fs::write(&path, format!("{text}{half}\n")).unwrap();
        assert_eq!(texts(&read(&path, 3, Some(tail.end), None).unwrap()), ["m10"]);
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
