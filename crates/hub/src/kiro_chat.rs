//! A Kiro agent's conversation as chat items, read from its `messages.jsonl` (features/0077).
//!
//! The items are the ones `chat` draws for Claude Code (`user`, `reply`, `tool`, `result`,
//! `event`), so the app needs nothing Kiro-specific; paging by byte offset is `chat::read_with`.

use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

use serde_json::{json, Value};

use crate::chat::{self, cut, first_line, output, Page, TEXT_CHARS};

/// Reads like `chat::read`: every item after byte `after`; else up to `limit` items ending at byte
/// `before` (the file's end when not given). Never loads more of the file than those items need.
pub fn read(path: &Path, limit: usize, after: Option<u64>, before: Option<u64>) -> std::io::Result<Page> {
    let mut page = chat::read_with(path, limit, after, before, || {
        let mut lines = Lines {
            path: Some(path),
            ..Lines::default()
        };
        move |at: u64, line: &str| {
            lines.at = at;
            lines.items(line)
        }
    })?;
    // A page of fewer items than asked for reached the file's start. Kiro writes lines before the
    // first message (`session_start`, `agent_note`) that show nothing, so the page would start
    // after them and "older" would offer a page with no items; nothing older holds any.
    if after.is_none() && page.items.len() < limit {
        page.start = 0;
    }
    Ok(page)
}

/// The texts Echo typed, plus how Kiro receives a first message that starts with a dash
/// (features/0072), so that message is still recognised as Echo's.
pub fn typed_inputs(inputs: &[(String, String)]) -> Vec<(String, String)> {
    let mut all = inputs.to_vec();
    all.extend(
        inputs
            .iter()
            .filter(|(_, text)| text.starts_with('-'))
            .map(|(origin, text)| (origin.clone(), format!("Message: {text}"))),
    );
    all
}

/// How far before a turn's last line the file is searched for the turn's error message.
const LOOKBACK: u64 = 64 << 10;

/// The parser of one range of lines. The line that ends a failed turn adds a note only when Kiro
/// gave no message for it: the range's own lines say so, else the file before `at` (the line's
/// offset in `path`), so where a page or a poll began does not change what shows.
#[derive(Default)]
struct Lines<'a> {
    error_shown: bool,
    path: Option<&'a Path>,
    at: u64,
}

impl Lines<'_> {
    /// The chat items of one `messages.jsonl` line, in order.
    ///
    /// - `user`: what was typed; reply: the model's text (its reasoning is not shown).
    /// - `tool`: one tool call by its `toolCallId`; `result`: its output, on a later line.
    /// - `event`: a turn that was cancelled or failed.
    /// Every other entry (turn and usage bookkeeping, hooks, steering and interaction records,
    /// the `session_start` prompt, the `<session_context>` note) is not the conversation.
    fn items(&mut self, line: &str) -> Vec<Value> {
        let Ok(entry) = serde_json::from_str::<Value>(line) else {
            return vec![];
        };
        let payload = &entry["payload"];
        let id = entry["id"].as_str().unwrap_or("");
        let at = &entry["timestamp"];
        match payload["type"].as_str() {
            Some("user") => typed(payload, id, at).into_iter().collect(),
            Some("assistant") => reply(payload, id, at).into_iter().collect(),
            Some("tool_call") => tool(payload, at),
            Some("tool_result") => vec![json!({
                "kind": "result",
                "id": payload["toolCallId"],
                "text": output(&payload["content"]),
                "error": payload["success"] == false,
            })],
            Some("turn_start") => {
                self.error_shown = false;
                vec![]
            }
            Some("session_metadata") if payload["key"] == "displayError" => {
                self.error_shown = true;
                let message = payload["value"]["message"].as_str().unwrap_or("The turn failed.");
                vec![note(id, &format!("Error: {message}"), "error", at)]
            }
            Some("turn_end") => match payload["stopReason"].as_str() {
                Some("cancelled") => vec![note(id, "Interrupted", "interrupt", at)],
                Some("error") if !self.error_shown && !self.has_message(payload) => {
                    vec![note(id, "Error: the turn failed.", "error", at)]
                }
                _ => vec![],
            },
            _ => vec![],
        }
    }
}

impl Lines<'_> {
    /// Whether Kiro wrote a `displayError` for the execution that `turn_end` ends, on the lines
    /// just before it (within `LOOKBACK`, and no earlier than the turn's start).
    fn has_message(&self, turn_end: &Value) -> bool {
        let Some(path) = self.path else { return false };
        let execution = &turn_end["executionId"];
        let from = self.at.saturating_sub(LOOKBACK);
        let Ok(mut file) = std::fs::File::open(path) else {
            return false;
        };
        let mut bytes = Vec::new();
        let read = file
            .seek(SeekFrom::Start(from))
            .and_then(|_| (&mut file).take(self.at - from).read_to_end(&mut bytes));
        if read.is_err() {
            return false;
        }
        let text = String::from_utf8_lossy(&bytes);
        // The first line may be cut by `from`; it fails to parse and is skipped.
        for line in text.lines().rev() {
            let Ok(entry) = serde_json::from_str::<Value>(line) else {
                continue;
            };
            let payload = &entry["payload"];
            match payload["type"].as_str() {
                Some("turn_start") | Some("turn_end") => return false,
                Some("session_metadata") if payload["key"] == "displayError" => {
                    if payload["executionId"] == *execution {
                        return true;
                    }
                }
                _ => {}
            }
        }
        false
    }
}

/// A background note in the conversation: an interrupt or an error, told apart by `level`.
fn note(id: &str, text: &str, level: &str, at: &Value) -> Value {
    json!({ "kind": "event", "id": id, "text": cut(text, TEXT_CHARS), "level": level, "at": at })
}

/// Blocks Kiro adds to what the human typed; they are not the human's words.
const INJECTED: [&str; 3] = ["<session_context>", "<system-reminder>", "[LIVE STEERING"];

/// A `user` entry: what was typed, or nothing. A message typed while a turn runs is written three
/// times: the text itself (`source: steer`), a synthetic copy wrapped in a steering notice, and an
/// empty entry that clears it; only the text is shown.
fn typed(payload: &Value, id: &str, at: &Value) -> Option<Value> {
    let kiro = &payload["_meta"]["kiro"];
    if kiro["syntheticUserMessageReason"].is_string() || kiro["steeringClearedIds"].is_array() {
        return None;
    }
    let text = payload["content"].as_str()?.trim();
    if text.is_empty() || INJECTED.iter().any(|tag| text.starts_with(tag)) {
        return None;
    }
    Some(json!({ "kind": "user", "id": id, "text": cut(text, TEXT_CHARS), "at": at }))
}

/// An `assistant` entry's text; `Reasoning` entries are the model thinking aloud.
fn reply(payload: &Value, id: &str, at: &Value) -> Option<Value> {
    if payload["operationType"].as_str().is_some_and(|kind| kind != "Say") {
        return None;
    }
    let text = payload["content"].as_str()?.trim();
    (!text.is_empty()).then(|| json!({ "kind": "reply", "id": id, "text": cut(text, TEXT_CHARS), "at": at }))
}

/// A tool call, named for the cards the app draws for Claude's tools, with its folded row
/// (`summary`) and expanded content. A call the human or a rule denied also gets its result
/// now, so the card reads as failed without waiting for Kiro's own result line.
fn tool(payload: &Value, at: &Value) -> Vec<Value> {
    let args = &payload["args"];
    let field = |key: &str| args[key].as_str().unwrap_or("");
    let path = [field("path"), payload["filePath"].as_str().unwrap_or("")]
        .into_iter()
        .find(|path| !path.is_empty())
        .unwrap_or("");
    let own = payload["toolName"].as_str().unwrap_or("Tool");
    let title = payload["title"].as_str().unwrap_or("");
    let (name, summary) = match own {
        "execute_bash" | "run_command" => ("Bash", first_line(field("command"))),
        "read_file" => ("Read", path.to_string()),
        "fs_write" => ("Write", path.to_string()),
        "str_replace" | "fs_append" => ("Edit", path.to_string()),
        _ => (own, other_summary(args)),
    };
    let summary = if summary.is_empty() { title.to_string() } else { summary };
    let id = payload["toolCallId"].clone();
    let mut item = json!({ "kind": "tool", "id": id, "tool": name, "summary": cut(&summary, 300), "at": at });
    match own {
        "execute_bash" | "run_command" => item["detail"] = json!(cut(field("command"), TEXT_CHARS)),
        "fs_write" => item["new"] = json!(cut(field("text"), TEXT_CHARS)),
        "str_replace" => {
            item["old"] = json!(cut(field("old_str"), TEXT_CHARS));
            item["new"] = json!(cut(field("new_str"), TEXT_CHARS));
        }
        "fs_append" => item["new"] = json!(cut(field("text"), TEXT_CHARS)),
        _ => {}
    }
    if payload["status"] != "denied" {
        return vec![item];
    }
    item["denied"] = json!(true);
    vec![
        item,
        json!({ "kind": "result", "id": id, "text": "Denied", "error": true }),
    ]
}

/// The folded row of a tool the app has no card for: its query, pattern, path or first text.
fn other_summary(args: &Value) -> String {
    ["query", "pattern", "path", "url"]
        .iter()
        .find_map(|key| args[key].as_str().filter(|text| !text.is_empty()))
        .or_else(|| args.as_object().and_then(|o| o.values().find_map(Value::as_str)))
        .map(first_line)
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture(name: &str) -> &'static str {
        match name {
            "single" => include_str!("../tests/fixtures/kiro/messages-single-turn.jsonl"),
            "tools" => include_str!("../tests/fixtures/kiro/messages-tool-approved.jsonl"),
            "error" => include_str!("../tests/fixtures/kiro/messages-failed.jsonl"),
            "cancelled" => include_str!("../tests/fixtures/kiro/messages-cancelled.jsonl"),
            "denied" => include_str!("../tests/fixtures/kiro/messages-denied.jsonl"),
            "two" => include_str!("../tests/fixtures/kiro/messages-two-turns.jsonl"),
            "broken" => include_str!("../tests/fixtures/kiro/messages-broken.jsonl"),
            other => panic!("no fixture {other}"),
        }
    }

    /// The items a whole fixture gives, read the way the chat reads it.
    fn all(name: &str) -> Vec<Value> {
        let mut lines = Lines::default();
        fixture(name).lines().flat_map(|line| lines.items(line)).collect()
    }

    /// (kind, text) of each item that has a text.
    fn shown(items: &[Value]) -> Vec<(String, String)> {
        items
            .iter()
            .filter(|item| item["kind"] != "result")
            .map(|item| {
                let text = item["text"].as_str().or(item["summary"].as_str()).unwrap_or("");
                (item["kind"].as_str().unwrap().to_string(), text.to_string())
            })
            .collect()
    }

    fn pair(kind: &str, text: &str) -> (String, String) {
        (kind.to_string(), text.to_string())
    }

    #[test]
    fn a_single_turn_shows_the_question_and_the_answer_only() {
        let items = all("single");
        assert_eq!(
            shown(&items),
            [
                pair("user", "What is the secret codeword? Reply with just the codeword."),
                pair("reply", "PINEAPPLE-42")
            ]
        );
        assert_eq!(items[1]["at"], "2026-11-13T09:31:30.100Z");
        assert!(items.iter().all(|item| !item["id"].as_str().unwrap().is_empty()));
    }

    #[test]
    fn an_approved_tool_call_and_its_result_are_the_cards_the_app_draws() {
        let items = all("tools");
        let kinds: Vec<_> = items.iter().map(|i| i["kind"].as_str().unwrap()).collect();
        assert_eq!(
            kinds,
            ["user", "tool", "result", "tool", "result", "tool", "result", "reply"]
        );
        let write = &items[1];
        assert_eq!(
            (write["tool"].as_str(), write["summary"].as_str()),
            (Some("Write"), Some("/tmp/kirospike-repo/w2.txt"))
        );
        assert_eq!(write["new"], "ws2");
        assert_eq!(items[2]["id"], write["id"], "a result is matched to its call by id");
        assert_eq!(items[2]["error"], false);
        let bash = &items[3];
        assert_eq!(
            (bash["tool"].as_str(), bash["summary"].as_str()),
            (Some("Bash"), Some("echo hi"))
        );
        assert_eq!(bash["detail"], "echo hi");
        assert_eq!(items[4]["text"], "Output:\nhi\n\n\nExit Code: 0");
        let read = &items[5];
        assert_eq!(
            (read["tool"].as_str(), read["summary"].as_str()),
            (Some("Read"), Some("/tmp/kirospike-repo/x.txt"))
        );
    }

    #[test]
    fn a_failed_turn_shows_kiros_message_once() {
        let items = all("error");
        assert_eq!(
            shown(&items),
            [
                pair("user", "hi"),
                pair(
                    "event",
                    "Error: The selected model is not available. Please select a different model and try again. (Request ID: 996c…)"
                )
            ]
        );
        assert_eq!(items[1]["level"], "error");
    }

    #[test]
    fn a_turn_that_failed_without_a_message_says_so() {
        let mut lines = Lines::default();
        let end = r#"{"id":"t-turn-end","timestamp":"2026-11-13T09:43:30.642Z","payload":{"type":"turn_end","stopReason":"error"}}"#;
        let got = lines.items(end);
        assert_eq!(
            (got[0]["kind"].as_str(), got[0]["text"].as_str()),
            (Some("event"), Some("Error: the turn failed."))
        );
    }

    #[test]
    fn a_cancelled_turn_shows_as_an_interrupt() {
        let items = all("cancelled");
        assert_eq!(
            shown(&items),
            [
                pair("user", "Write a 600-word story about a lighthouse keeper. No tools."),
                pair("reply", "The keeper climbed the stairs."),
                pair("event", "Interrupted")
            ]
        );
        assert_eq!(items[2]["level"], "interrupt");
    }

    #[test]
    fn a_denied_tool_call_shows_as_denied_and_failed() {
        let items = all("denied");
        let tool = items.iter().find(|i| i["kind"] == "tool").unwrap();
        assert_eq!(
            (tool["tool"].as_str(), tool["summary"].as_str()),
            (Some("Bash"), Some("touch y"))
        );
        assert_eq!(tool["denied"], true);
        let results: Vec<_> = items.iter().filter(|i| i["kind"] == "result").collect();
        assert_eq!(results.len(), 2, "its own Denied result, then Kiro's");
        assert!(results.iter().all(|r| r["id"] == tool["id"] && r["error"] == true));
        assert_eq!(results[0]["text"], "Denied");
        assert!(results[1]["text"]
            .as_str()
            .unwrap()
            .contains("The user rejected this tool call."));
    }

    #[test]
    fn two_turns_and_a_steered_message_show_each_text_once() {
        let items = all("two");
        assert_eq!(
            shown(&items),
            [
                pair("user", "Reply with the single word ok."),
                pair("reply", "ok"),
                pair("user", "Now say hi."),
                pair("user", "Do not run it. Just say ok."),
                pair("reply", "hi")
            ]
        );
    }

    #[test]
    fn injected_blocks_are_not_the_humans_words() {
        let mut lines = Lines::default();
        for content in [
            "<session_context>\nThe current model is claude-haiku-5.5.\n</session_context>",
            "  ",
            "",
        ] {
            let user = json!({ "id": "u", "payload": { "type": "user", "content": content } });
            assert!(lines.items(&user.to_string()).is_empty(), "{content:?}");
        }
        // A `<` that starts a real message is still the human's.
        let html = json!({ "id": "u", "payload": { "type": "user", "content": "<b>bold</b> please" } });
        assert_eq!(lines.items(&html.to_string())[0]["text"], "<b>bold</b> please");
    }

    #[test]
    fn echos_texts_are_marked_even_after_the_dash_guard() {
        let echo = [("orchestrator".to_string(), "-d sess_1: fix it".to_string())];
        let mut got = vec![
            json!({ "kind": "user", "text": "Message: -d sess_1: fix it" }),
            json!({ "kind": "user", "text": "-d sess_1: fix it" }),
            json!({ "kind": "user", "text": "something else" }),
        ];
        chat::mark_origins(&mut got, &typed_inputs(&echo));
        assert_eq!(
            (got[0]["from"].as_str(), got[1]["from"].as_str()),
            (Some("orchestrator"), Some("orchestrator"))
        );
        assert!(got[2].get("from").is_none());
    }

    #[test]
    fn a_line_that_is_not_json_or_is_cut_short_is_skipped() {
        assert_eq!(
            shown(&all("broken")),
            [
                pair("user", "hi"),
                pair("reply", "hello"),
                pair("user", "after the noise")
            ]
        );
        // Read from a file, the cut last line is left for the next read: `end` stops before it.
        let text = fixture("broken");
        let (dir, path) = planted("broken", text);
        let page = read(&path, 100, None, None).unwrap();
        assert_eq!(texts(&page), ["hi", "hello", "after the noise"]);
        assert_eq!(page.end as usize, text.rfind('\n').unwrap() + 1);
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// The fixture as a file in a temp folder, for the paging tests.
    fn planted(name: &str, text: &str) -> (std::path::PathBuf, std::path::PathBuf) {
        let dir = std::env::temp_dir().join(format!("hub-kiro-chat-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("messages.jsonl");
        std::fs::write(&path, text).unwrap();
        (dir, path)
    }

    fn texts(page: &Page) -> Vec<String> {
        page.items
            .iter()
            .filter(|item| item["kind"] == "user" || item["kind"] == "reply")
            .map(|item| item["text"].as_str().unwrap().to_string())
            .collect()
    }

    #[test]
    fn reading_takes_the_tail_then_pages_back_to_the_start() {
        let text = fixture("two");
        let (dir, path) = planted("paging", text);
        let all = read(&path, 100, None, None).unwrap();
        assert_eq!((all.start, all.end), (0, text.len() as u64));
        // The last two items, then the two before them, then the rest.
        let tail = read(&path, 2, None, None).unwrap();
        assert_eq!(texts(&tail), ["Do not run it. Just say ok.", "hi"]);
        assert_eq!(tail.end, text.len() as u64);
        let older = read(&path, 2, None, Some(tail.start)).unwrap();
        assert_eq!(texts(&older), ["ok", "Now say hi."]);
        let oldest = read(&path, 10, None, Some(older.start)).unwrap();
        assert_eq!(
            (texts(&oldest), oldest.start),
            (vec!["Reply with the single word ok.".to_string()], 0)
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn reading_after_an_offset_gives_only_whole_new_lines() {
        let text = fixture("single");
        let (dir, path) = planted("after", text);
        let first = read(&path, 100, None, None).unwrap();
        assert_eq!(texts(&first).len(), 2);
        // A turn being written: half a line waits, the whole line arrives with the next read.
        let more = r#"{"id":"u2","timestamp":"2026-11-13T09:32:00.000Z","payload":{"type":"user","content":"thanks"}}"#;
        std::fs::write(&path, format!("{text}{}", &more[..30])).unwrap();
        let waiting = read(&path, 100, Some(first.end), None).unwrap();
        assert_eq!((waiting.items.len(), waiting.end), (0, first.end));
        std::fs::write(&path, format!("{text}{more}\n")).unwrap();
        let next = read(&path, 100, Some(first.end), None).unwrap();
        assert_eq!(texts(&next), ["thanks"]);
        std::fs::remove_dir_all(dir).unwrap();
    }

    /// The error notes of a page.
    fn errors(page: &Page) -> Vec<String> {
        page.items
            .iter()
            .filter(|item| item["level"] == "error")
            .map(|item| item["text"].as_str().unwrap().to_string())
            .collect()
    }

    /// The byte offset after the first `n` lines of `text`.
    fn after_lines(text: &str, n: usize) -> usize {
        text.split_inclusive('\n').take(n).map(str::len).sum()
    }

    const KIRO_MESSAGE: &str = "Error: The selected model is not available. Please select a different model and try again. (Request ID: 996c…)";

    #[test]
    fn a_failed_turn_read_whole_shows_the_message_once() {
        let (dir, path) = planted("error-whole", fixture("error"));
        let page = read(&path, 100, None, None).unwrap();
        assert_eq!(errors(&page), [KIRO_MESSAGE]);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_failed_turn_split_across_two_polls_shows_the_message_once() {
        let text = fixture("error");
        let (dir, path) = planted("error-after", &text[..after_lines(text, 6)]);
        // The first poll ends on the `displayError` line; the line that ends the turn lands later.
        let first = read(&path, 100, None, None).unwrap();
        assert_eq!(errors(&first), [KIRO_MESSAGE]);
        std::fs::write(&path, text).unwrap();
        let next = read(&path, 100, Some(first.end), None).unwrap();
        assert_eq!(errors(&next), Vec::<String>::new());
        // A poll that starts on the line that ends the turn gives the same.
        let last = read(&path, 100, Some(after_lines(text, 8) as u64), None).unwrap();
        assert_eq!(errors(&last), Vec::<String>::new());
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_failed_turn_read_from_the_tail_shows_the_message_not_a_generic_line() {
        // The first window of a tail read starts between the message and the turn's end.
        let padding = |bytes: usize| {
            format!(
                "{}\n",
                json!({"id": "", "payload": {"type": "agent_note", "content": "x".repeat(bytes)}})
            )
        };
        let lines: Vec<&str> = fixture("error").lines().collect();
        let head = lines[..6].join("\n") + "\n";
        let middle = padding(4000);
        let end = lines[6..].join("\n") + "\n";
        let window = 2usize << 20;
        let before_end = head.len() + middle.len() / 2;
        let mut text = head + &middle + &end;
        let fill = (before_end + window).saturating_sub(text.len());
        text += &padding(fill - padding(0).len());
        assert_eq!(text.len() - window, before_end);
        let (dir, path) = planted("error-tail", &text);
        let tail = read(&path, 1, None, None).unwrap();
        assert_eq!(errors(&tail), [KIRO_MESSAGE]);
        let whole = read(&path, 100, None, None).unwrap();
        assert_eq!(errors(&whole), [KIRO_MESSAGE]);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_failed_turn_with_no_message_shows_one_generic_line_wherever_it_is_read_from() {
        let text = fixture("error");
        let without: String = text
            .lines()
            .filter(|line| !line.contains("displayError"))
            .map(|l| format!("{l}\n"))
            .collect();
        let (dir, path) = planted("error-bare", &without);
        let whole = read(&path, 100, None, None).unwrap();
        let end = read(&path, 100, Some(after_lines(&without, 7) as u64), None).unwrap();
        assert_eq!(
            (errors(&whole), errors(&end)),
            (
                vec!["Error: the turn failed.".to_string()],
                vec!["Error: the turn failed.".to_string()]
            )
        );
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn a_missing_file_is_an_error_the_caller_turns_into_no_items() {
        assert!(read(Path::new("/nonexistent/messages.jsonl"), 10, None, None).is_err());
    }
}
