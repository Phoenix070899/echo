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
}
