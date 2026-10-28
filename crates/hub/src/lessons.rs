//! Lessons and Preferences: plain Markdown files in the daemon's state, so any agent CLI can read
//! them. Both live under `memory/`, the one state folder agents may edit: Lessons are one repo's
//! (`memory/repos/<name>-<hash>/lessons.md`); Preferences are the human's, for every repo
//! (`memory/preferences.md`).

use anyhow::Result;
use std::path::{Path, PathBuf};

use crate::paths;

/// Past this many lessons the Orchestrator is asked to have them merged.
pub const LIMIT: usize = 60;

/// Heads the Lessons in a Worker's or Orchestrator's prompt.
pub const WORKER_INTRO: &str = "# Lessons for this repo\n\n\
    What earlier Workers learned here. Rely on them, and say in your Final Report when one proved wrong.";

const LESSONS_HEAD: &str = "# Lessons\n\n\
    Facts about this repo that Workers learned the hard way, one per line, newest last.\n\
    Added by `echoctl done --lesson`; merged and pruned by an `ino` Worker.\n\n";

/// What agents may read and edit in the daemon's state; nothing else of it is theirs.
pub fn memory_dir(state: &Path) -> PathBuf {
    state.join("memory")
}

/// One repo's folder in the daemon's state: its main checkout's folder name, then a hash of its
/// path, so two repos with one folder name keep apart.
pub fn repo_dir(state: &Path, repo: &str) -> PathBuf {
    let name = Path::new(repo)
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "repo".into());
    // FNV-1a: stable across Rust releases, unlike the std hasher.
    let hash = repo
        .bytes()
        .fold(0xcbf29ce484222325u64, |h, b| (h ^ b as u64).wrapping_mul(0x100000001b3));
    memory_dir(state)
        .join("repos")
        .join(format!("{name}-{:08x}", hash as u32))
}

pub fn lessons_path(state: &Path, repo: &str) -> PathBuf {
    repo_dir(state, repo).join("lessons.md")
}

/// The repo's lessons, or "" when it has none yet.
pub fn lessons(state: &Path, repo: &str) -> String {
    let text = std::fs::read_to_string(lessons_path(state, repo)).unwrap_or_default();
    if count(&text) == 0 {
        String::new()
    } else {
        text
    }
}

/// Adds each lesson as a bullet dated `today` (YYYY-MM-DD) and signed by `worker` (w12), and
/// returns how many lessons the file holds now.
pub fn add(state: &Path, repo: &str, worker: &str, today: &str, new: &[String]) -> Result<usize> {
    let path = lessons_path(state, repo);
    let mut text = std::fs::read_to_string(&path).unwrap_or_else(|_| LESSONS_HEAD.to_string());
    for lesson in new {
        let line = lesson.split_whitespace().collect::<Vec<_>>().join(" ");
        if line.is_empty() {
            continue;
        }
        if !text.ends_with('\n') {
            text.push('\n');
        }
        text += &format!("- {line} ({today}, {worker})\n");
    }
    std::fs::create_dir_all(path.parent().unwrap())?;
    std::fs::write(&path, &text)?;
    Ok(count(&text))
}

fn count(text: &str) -> usize {
    text.lines().filter(|line| line.starts_with("- ")).count()
}

/// The human's Preferences, in the state folder. The first time, they come from the echo repo's
/// `memory/preferences.md`, where they lived before.
pub fn preferences_path(state: &Path, hub: &Path) -> PathBuf {
    // Made here, as every agent's start reads Preferences, so `--add-dir` names a real folder.
    let _ = std::fs::create_dir_all(memory_dir(state));
    let path = memory_dir(state).join("preferences.md");
    if !path.exists() {
        if let Ok(old) = std::fs::read_to_string(hub.join("memory").join("preferences.md")) {
            let _ = std::fs::write(&path, old);
        }
    }
    path
}

pub fn preferences(hub: &Path) -> String {
    std::fs::read_to_string(preferences_path(&paths::state_dir(), hub)).unwrap_or_default()
}

/// One bullet of a Preferences or Lessons file, under the `## ` heading it sits in ("" for none).
#[derive(Debug, Clone, PartialEq, serde::Serialize)]
pub struct Bullet {
    pub section: String,
    /// The line as written, without "- ": the handle to remove it by.
    pub text: String,
}

pub fn bullets(text: &str) -> Vec<Bullet> {
    let mut section = String::new();
    let mut out = Vec::new();
    for line in text.lines() {
        if let Some(heading) = line.strip_prefix("## ") {
            section = heading.trim().to_string();
        } else if let Some(bullet) = line.strip_prefix("- ") {
            out.push(Bullet {
                section: section.clone(),
                text: bullet.to_string(),
            });
        }
    }
    out
}

/// The `## ` headings of a file, in order.
pub fn sections(text: &str) -> Vec<String> {
    text.lines()
        .filter_map(|l| l.strip_prefix("## "))
        .map(|h| h.trim().to_string())
        .collect()
}

/// Deletes the bullet written exactly as `bullet`; fails when the file no longer has it.
pub fn remove(path: &Path, bullet: &str) -> Result<()> {
    let text = std::fs::read_to_string(path)?;
    let line = format!("- {bullet}");
    let Some(at) = text.lines().position(|l| l == line) else {
        anyhow::bail!(
            "{} no longer has that line; it may have changed meanwhile",
            path.display()
        );
    };
    let kept: Vec<&str> = text
        .lines()
        .enumerate()
        .filter(|(i, _)| *i != at)
        .map(|(_, l)| l)
        .collect();
    std::fs::write(path, kept.join("\n") + "\n")?;
    Ok(())
}

/// Adds a dated bullet at the end of `section`'s bullets, or at the end of the file when it has
/// no such heading.
pub fn add_to_section(path: &Path, section: &str, bullet: &str, today: &str) -> Result<()> {
    let line = bullet.split_whitespace().collect::<Vec<_>>().join(" ");
    if line.is_empty() {
        anyhow::bail!("a line needs some text");
    }
    let text = std::fs::read_to_string(path).unwrap_or_default();
    let mut lines: Vec<String> = text.lines().map(String::from).collect();
    let new = format!("- {line} ({today})");
    let heading = lines
        .iter()
        .position(|l| l.strip_prefix("## ").is_some_and(|h| h.trim() == section));
    match heading {
        Some(at) => {
            // After the section's last non-blank line, before the next heading.
            let end = lines[at + 1..]
                .iter()
                .position(|l| l.starts_with("## "))
                .map_or(lines.len(), |n| at + 1 + n);
            let last = (at..end).rev().find(|&i| !lines[i].trim().is_empty()).unwrap_or(at);
            let blank_after_heading = last == at;
            lines.insert(last + 1, new);
            if blank_after_heading {
                lines.insert(last + 1, String::new());
            }
        }
        None => lines.push(new),
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, lines.join("\n") + "\n")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hub-lessons-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn lessons_are_dated_signed_and_counted() {
        let state = scratch("add");
        assert_eq!(lessons(&state, "/code/shop"), "");
        let n = add(
            &state,
            "/code/shop",
            "w3",
            "2026-10-28",
            &["Run `make db`\n before the tests".into(), " ".into()],
        )
        .unwrap();
        assert_eq!(n, 1);
        let n = add(&state, "/code/shop", "w4", "2026-10-29", &["Port 5173 is taken".into()]).unwrap();
        assert_eq!(n, 2);
        let text = lessons(&state, "/code/shop");
        assert!(text.starts_with("# Lessons"));
        assert!(text.contains("- Run `make db` before the tests (2026-10-28, w3)\n"));
        assert!(text.ends_with("- Port 5173 is taken (2026-10-29, w4)\n"));
    }

    #[test]
    fn two_repos_with_one_folder_name_keep_apart() {
        let state = Path::new("/s");
        let a = repo_dir(state, "/work/app");
        let b = repo_dir(state, "/home/app");
        assert_ne!(a, b);
        assert!(a.file_name().unwrap().to_string_lossy().starts_with("app-"));
        assert_eq!(a, repo_dir(state, "/work/app"));
    }

    #[test]
    fn preferences_move_from_the_echo_repo_once() {
        let state = scratch("prefs-state");
        let hub = scratch("prefs-hub");
        std::fs::create_dir_all(hub.join("memory")).unwrap();
        std::fs::write(hub.join("memory/preferences.md"), "- Old rule\n").unwrap();
        let path = preferences_path(&state, &hub);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "- Old rule\n");
        std::fs::write(&path, "- Mine\n").unwrap();
        preferences_path(&state, &hub);
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "- Mine\n", "kept once moved");
    }

    #[test]
    fn bullets_are_read_added_under_their_heading_and_removed() {
        let dir = scratch("edit");
        let path = dir.join("preferences.md");
        std::fs::write(
            &path,
            "# User preferences\n\nIntro.\n\n## Workflow\n\n- Push after review (2026-10-01)\n\n## Never do\n",
        )
        .unwrap();
        add_to_section(&path, "Never do", "Commit to   main", "2026-10-28").unwrap();
        add_to_section(&path, "Workflow", "Draft PRs first", "2026-10-28").unwrap();
        let text = std::fs::read_to_string(&path).unwrap();
        assert_eq!(
            bullets(&text),
            [
                Bullet {
                    section: "Workflow".into(),
                    text: "Push after review (2026-10-01)".into()
                },
                Bullet {
                    section: "Workflow".into(),
                    text: "Draft PRs first (2026-10-28)".into()
                },
                Bullet {
                    section: "Never do".into(),
                    text: "Commit to main (2026-10-28)".into()
                },
            ]
        );
        assert!(text.contains("## Never do\n\n- Commit to main"), "{text}");
        assert_eq!(sections(&text), ["Workflow", "Never do"]);
        remove(&path, "Push after review (2026-10-01)").unwrap();
        assert!(remove(&path, "Push after review (2026-10-01)").is_err());
        assert_eq!(bullets(&std::fs::read_to_string(&path).unwrap()).len(), 2);
    }
}
