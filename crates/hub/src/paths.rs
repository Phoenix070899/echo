//! Where Echo keeps its files.

use std::path::{Path, PathBuf};

/// The echo repo (profiles, Worker Contract, prompts). `ECHO_REPO` overrides the build location.
pub fn hub_dir() -> PathBuf {
    if let Some(dir) = std::env::var_os("ECHO_REPO") {
        return PathBuf::from(dir);
    }
    let built = PathBuf::from(concat!(env!("CARGO_MANIFEST_DIR"), "/../.."));
    built.canonicalize().unwrap_or(built)
}

/// The Hub Daemon's own files. `HUB_STATE` overrides `~/.echo`; set but empty counts as
/// unset, as the app reads it, rather than as the current directory.
pub fn state_dir() -> PathBuf {
    state_dir_from(std::env::var_os("HUB_STATE"))
}

fn state_dir_from(hub_state: Option<std::ffi::OsString>) -> PathBuf {
    match hub_state.filter(|dir| !dir.is_empty()) {
        Some(dir) => PathBuf::from(dir),
        None => default_state(&home()),
    }
}

/// `~/.echo`. State from before the rename, in `~/.agent-hub`, moves there the first time no
/// daemon holds it, and `~/.agent-hub` stays as a link to it, so the worktrees and paths stored
/// under the old name still resolve. While a daemon still runs there, the old folder is used.
fn default_state(home: &Path) -> PathBuf {
    let new = home.join(".echo");
    let old = home.join(".agent-hub");
    let moved = std::fs::symlink_metadata(&old).is_ok_and(|meta| meta.file_type().is_symlink());
    if new.exists() || moved || !old.is_dir() {
        return new;
    }
    if daemon_holds(&old) || std::fs::rename(&old, &new).is_err() {
        return old;
    }
    let _ = std::os::unix::fs::symlink(".echo", &old);
    new
}

/// A daemon runs on this state folder: it holds `hubd.lock` for as long as it lives.
fn daemon_holds(state: &Path) -> bool {
    let Ok(lock) = std::fs::File::open(state.join("hubd.lock")) else {
        return false;
    };
    // Dropping the file releases a lock taken here.
    unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_SH | libc::LOCK_NB) != 0 }
}

pub fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").expect("HOME is set"))
}

pub fn socket() -> PathBuf {
    state_dir().join("hubd.sock")
}

pub fn database() -> PathBuf {
    state_dir().join("hub.db")
}

pub fn log() -> PathBuf {
    state_dir().join("hubd.log")
}

pub fn worktrees() -> PathBuf {
    state_dir().join("worktrees")
}

/// Claude Code's transcript for a session, once its first turn has started.
pub fn transcript_exists(session_id: &str) -> bool {
    let Ok(projects) = std::fs::read_dir(home().join(".claude").join("projects")) else {
        return false;
    };
    let file = format!("{session_id}.jsonl");
    projects.flatten().any(|project| project.path().join(&file).exists())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_hub_state_means_the_default() {
        let default = default_state(&home());
        assert_eq!(state_dir_from(None), default);
        assert_eq!(state_dir_from(Some("".into())), default);
        assert_eq!(state_dir_from(Some("/tmp/hub".into())), PathBuf::from("/tmp/hub"));
    }

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("echo-paths-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn old_state_moves_to_echo_and_leaves_a_link() {
        let home = scratch("move");
        std::fs::create_dir(home.join(".agent-hub")).unwrap();
        std::fs::write(home.join(".agent-hub/hub.db"), "db").unwrap();
        assert_eq!(default_state(&home), home.join(".echo"));
        assert_eq!(std::fs::read_to_string(home.join(".echo/hub.db")).unwrap(), "db");
        assert_eq!(std::fs::read_to_string(home.join(".agent-hub/hub.db")).unwrap(), "db");
        assert_eq!(default_state(&home), home.join(".echo"));
        std::fs::remove_dir_all(&home).unwrap();
    }

    #[test]
    fn old_state_stays_while_its_daemon_runs() {
        let home = scratch("held");
        std::fs::create_dir(home.join(".agent-hub")).unwrap();
        let lock = std::fs::File::create(home.join(".agent-hub/hubd.lock")).unwrap();
        assert_eq!(
            unsafe { libc::flock(std::os::fd::AsRawFd::as_raw_fd(&lock), libc::LOCK_EX | libc::LOCK_NB) },
            0
        );
        assert_eq!(default_state(&home), home.join(".agent-hub"));
        assert!(!home.join(".echo").exists());
        drop(lock);
        assert_eq!(default_state(&home), home.join(".echo"));
        std::fs::remove_dir_all(&home).unwrap();
    }
}
