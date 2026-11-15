//! Echo's own sign-in for each agent CLI (decisions/features/0089). Claude Code and Codex keep a
//! login of Echo's in `accounts/<cli>` under the state folder: a config folder that links to the
//! human's own config, all but the login. Agents and Workers run on it while it is signed in, and
//! on the human's own login otherwise. Kiro keeps one login for the whole Mac, so it has none.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use base64::engine::general_purpose::URL_SAFE_NO_PAD as B64;
use base64::Engine;
use serde_json::{json, Value};

use crate::cli::Cli;
use crate::paths;

/// The CLIs Settings lists, in its order.
pub const ALL: [Cli; 3] = [Cli::Claude, Cli::Codex, Cli::Kiro];

/// A status command only reads local files; this is generous.
const STATUS_LIMIT: Duration = Duration::from_secs(15);

/// The variable that moves the CLI's config folder, login included; Kiro has none that moves its login.
pub fn home_var(cli: Cli) -> Option<&'static str> {
    match cli {
        Cli::Claude => Some("CLAUDE_CONFIG_DIR"),
        Cli::Codex => Some("CODEX_HOME"),
        Cli::Kiro => None,
    }
}

/// Echo's config folder for `cli`.
pub fn dir(state: &Path, cli: Cli) -> PathBuf {
    state.join("accounts").join(cli.name())
}

/// Present while Echo's own login for `cli` is signed in, as its last status read said.
fn marker(state: &Path, cli: Cli) -> PathBuf {
    state.join("accounts").join(format!("{}.signed-in", cli.name()))
}

/// Echo's own login for `cli` is signed in, so agents run on it.
pub fn own(state: &Path, cli: Cli) -> bool {
    home_var(cli).is_some() && marker(state, cli).exists()
}

/// What an agent or Worker starts with: each CLI's config folder moved to Echo's while Echo's own
/// login is signed in. Both are set, whichever CLI runs, so a CLI an agent runs itself uses Echo's
/// login too.
pub fn env(state: &Path) -> Vec<(String, String)> {
    ALL.into_iter()
        .filter(|cli| own(state, *cli))
        .filter_map(|cli| Some((home_var(cli)?.to_string(), dir(state, cli).display().to_string())))
        .collect()
}

/// The human's own config folder for `cli`, as the daemon's environment names it.
fn source(cli: Cli) -> Option<PathBuf> {
    let var = home_var(cli)?;
    let default = match cli {
        Cli::Claude => ".claude",
        _ => ".codex",
    };
    Some(
        std::env::var_os(var)
            .filter(|dir| !dir.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| paths::home().join(default)),
    )
}

/// The files of the config folder that are the login itself, never linked.
fn private(cli: Cli) -> &'static [&'static str] {
    match cli {
        Cli::Claude => &[".credentials.json", ".claude.json"],
        _ => &["auth.json"],
    }
}

/// Makes Echo's config folder for `cli` and links into it everything in the human's own but the
/// login: settings, instructions, skills, plugins, transcripts. Run again before each sign-in and
/// each start, it adds what the human's folder gained and drops links to what it lost.
pub fn prepare(state: &Path, cli: Cli) -> Result<PathBuf> {
    let source = source(cli).context("no config folder of its own")?;
    prepare_from(state, cli, &source)
}

fn prepare_from(state: &Path, cli: Cli, source: &Path) -> Result<PathBuf> {
    let dir = dir(state, cli);
    std::fs::create_dir_all(&dir).with_context(|| format!("making {}", dir.display()))?;
    for entry in std::fs::read_dir(&dir)?.flatten() {
        let path = entry.path();
        let gone = std::fs::symlink_metadata(&path).is_ok_and(|meta| meta.file_type().is_symlink()) && !path.exists();
        if gone {
            std::fs::remove_file(&path)?;
        }
    }
    if let Ok(entries) = std::fs::read_dir(source) {
        for entry in entries.flatten() {
            let name = entry.file_name();
            let link = dir.join(&name);
            if private(cli).iter().any(|p| name == *p) || std::fs::symlink_metadata(&link).is_ok() {
                continue;
            }
            std::os::unix::fs::symlink(entry.path(), &link).with_context(|| format!("linking {}", link.display()))?;
        }
    }
    if cli == Cli::Claude {
        copy_claude_json(source, &dir)?;
    }
    Ok(dir)
}

/// Claude Code keeps its global config (MCP servers, trusted folders) in `.claude.json`, beside the
/// config folder unless that folder was moved. Echo's starts as a copy of the human's without the
/// account it names, since a sign-in writes its own account there.
fn copy_claude_json(source: &Path, dir: &Path) -> Result<()> {
    let target = dir.join(".claude.json");
    if target.exists() {
        return Ok(());
    }
    let inside = source.join(".claude.json");
    let from = if inside.exists() {
        inside
    } else {
        source.parent().unwrap_or(source).join(".claude.json")
    };
    let Ok(text) = std::fs::read_to_string(&from) else {
        return Ok(());
    };
    let Ok(Value::Object(mut config)) = serde_json::from_str::<Value>(&text) else {
        return Ok(());
    };
    config.remove("oauthAccount");
    std::fs::write(&target, serde_json::to_string_pretty(&Value::Object(config))?)?;
    Ok(())
}

/// The program and arguments that sign in to `cli`, run in a terminal Echo shows.
pub fn login_args(cli: Cli) -> Result<Vec<String>> {
    Ok(match cli {
        Cli::Claude => vec!["auth".into(), "login".into()],
        Cli::Codex => vec!["login".into()],
        Cli::Kiro => bail!("Kiro keeps one login for this Mac; sign in with `kiro-cli login` in a terminal"),
    })
}

/// One CLI's login, as Settings shows it.
#[derive(Debug, Default, PartialEq)]
pub struct Status {
    pub installed: bool,
    /// Echo's own login is signed in, and agents run on it.
    pub own: bool,
    /// Agents can run: on Echo's login or the human's.
    pub signed_in: bool,
    /// Who they run as: an email, or how the CLI is signed in.
    pub account: Option<String>,
}

impl Status {
    pub fn view(&self, cli: Cli) -> Value {
        json!({
            "cli": cli.name(),
            "installed": self.installed,
            "own": self.own,
            "signedIn": self.signed_in,
            "account": self.account,
            "shared": home_var(cli).is_none(),
        })
    }
}

/// Reads `cli`'s login: Echo's own first, then the human's, and keeps the marker in step with
/// Echo's. `program` stands in for the CLI under test.
pub fn status(state: &Path, cli: Cli, program: &str) -> Status {
    let dir = dir(state, cli);
    if home_var(cli).is_some() && dir.is_dir() {
        let own = read(cli, program, Some(&dir));
        if own.signed_in {
            let _ = std::fs::write(marker(state, cli), "");
            return Status { own: true, ..own };
        }
    }
    let _ = std::fs::remove_file(marker(state, cli));
    read(cli, program, None)
}

/// Signs Echo's own login for `cli` out; agents go back to the human's.
pub fn sign_out(state: &Path, cli: Cli, program: &str) -> Result<()> {
    let var = home_var(cli).context("Kiro keeps one login for this Mac; Echo does not sign it out")?;
    let args: &[&str] = match cli {
        Cli::Claude => &["auth", "logout"],
        _ => &["logout"],
    };
    let dir = dir(state, cli);
    let _ = std::fs::remove_file(marker(state, cli));
    if dir.is_dir() {
        run(program, args, Some((var, &dir)))?;
    }
    Ok(())
}

/// One status read, on Echo's config folder (`dir`) or the human's.
fn read(cli: Cli, program: &str, dir: Option<&Path>) -> Status {
    let home = dir.and_then(|dir| Some((home_var(cli)?, dir)));
    let args: &[&str] = match cli {
        Cli::Claude => &["auth", "status"],
        Cli::Codex => &["login", "status"],
        Cli::Kiro => &["whoami"],
    };
    let Ok(Some((ok, out))) = run(program, args, home) else {
        return Status {
            installed: false,
            ..Status::default()
        };
    };
    match cli {
        Cli::Claude => {
            let answer: Value = serde_json::from_str(out.trim()).unwrap_or_default();
            let signed_in = answer["loggedIn"].as_bool().unwrap_or(false);
            let account = answer["email"]
                .as_str()
                .map(String::from)
                .or_else(|| signed_in.then(|| answer["authMethod"].as_str().unwrap_or("signed in").to_string()));
            Status {
                installed: true,
                own: false,
                signed_in,
                account: account.filter(|_| signed_in),
            }
        }
        Cli::Codex => {
            let signed_in = ok && !out.to_lowercase().contains("not logged in");
            let folder = dir.map(Path::to_path_buf).or_else(|| source(cli));
            let account = folder
                .and_then(|folder| codex_email(&folder))
                .or_else(|| signed_in.then(|| out.trim().trim_start_matches("Logged in using ").to_string()));
            Status {
                installed: true,
                own: false,
                signed_in,
                account: account.filter(|_| signed_in),
            }
        }
        Cli::Kiro => {
            let account = out
                .lines()
                .find_map(|line| line.trim().strip_prefix("Email:"))
                .map(|email| email.trim().to_string());
            Status {
                installed: true,
                own: false,
                signed_in: ok,
                account: account.filter(|_| ok),
            }
        }
    }
}

/// The email in Codex's ChatGPT login: the `email` claim of its id token.
fn codex_email(folder: &Path) -> Option<String> {
    let auth: Value = serde_json::from_str(&std::fs::read_to_string(folder.join("auth.json")).ok()?).ok()?;
    let token = auth["tokens"]["id_token"].as_str()?;
    let payload = B64.decode(token.split('.').nth(1)?.trim_end_matches('=')).ok()?;
    let claims: Value = serde_json::from_slice(&payload).ok()?;
    claims["email"].as_str().map(String::from)
}

/// Runs `program args` with `home` set, if given; None when the program is not there. Gives the
/// exit status and what it printed.
fn run(program: &str, args: &[&str], home: Option<(&str, &Path)>) -> Result<Option<(bool, String)>> {
    let mut command = Command::new(program);
    command
        .args(args)
        .current_dir(std::env::temp_dir())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if let Some((var, dir)) = home {
        command.env(var, dir);
    }
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(error).with_context(|| format!("running {program} {}", args.join(" "))),
    };
    let deadline = Instant::now() + STATUS_LIMIT;
    loop {
        if child.try_wait()?.is_some() {
            break;
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            bail!(
                "`{program} {}` took over {} seconds",
                args.join(" "),
                STATUS_LIMIT.as_secs()
            );
        }
        std::thread::sleep(Duration::from_millis(25));
    }
    let output = child.wait_with_output()?;
    Ok(Some((
        output.status.success(),
        String::from_utf8_lossy(&output.stdout).into_owned(),
    )))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("echo-accounts-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn fake() -> String {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fake-agent.sh").to_string()
    }

    #[test]
    fn echos_folder_links_everything_but_the_login_and_copies_the_global_config_without_its_account() {
        let root = scratch("links");
        let human = root.join("home/.claude");
        std::fs::create_dir_all(human.join("skills")).unwrap();
        std::fs::write(human.join("settings.json"), "{}").unwrap();
        std::fs::write(human.join(".credentials.json"), "secret").unwrap();
        std::fs::write(
            root.join("home/.claude.json"),
            r#"{"mcpServers": {"x": {}}, "oauthAccount": {"emailAddress": "human@example.com"}}"#,
        )
        .unwrap();
        let state = root.join("state");
        let dir = prepare_from(&state, Cli::Claude, &human).unwrap();
        assert_eq!(std::fs::read_link(dir.join("skills")).unwrap(), human.join("skills"));
        assert_eq!(
            std::fs::read_link(dir.join("settings.json")).unwrap(),
            human.join("settings.json")
        );
        assert!(!dir.join(".credentials.json").exists());
        let config: Value = serde_json::from_str(&std::fs::read_to_string(dir.join(".claude.json")).unwrap()).unwrap();
        assert!(config.get("mcpServers").is_some());
        assert!(config.get("oauthAccount").is_none());

        // The human's folder gains a file and loses one: the links follow, Echo's own config stays.
        std::fs::write(human.join("CLAUDE.md"), "rules").unwrap();
        std::fs::remove_file(human.join("settings.json")).unwrap();
        std::fs::write(dir.join(".claude.json"), "{}").unwrap();
        prepare_from(&state, Cli::Claude, &human).unwrap();
        assert!(dir.join("CLAUDE.md").exists());
        assert!(std::fs::symlink_metadata(dir.join("settings.json")).is_err());
        assert_eq!(std::fs::read_to_string(dir.join(".claude.json")).unwrap(), "{}");
    }

    #[test]
    fn codexs_folder_never_links_its_login() {
        let root = scratch("codex");
        let human = root.join(".codex");
        std::fs::create_dir_all(human.join("sessions")).unwrap();
        std::fs::write(human.join("auth.json"), "{}").unwrap();
        std::fs::write(human.join("config.toml"), "").unwrap();
        let dir = prepare_from(&root.join("state"), Cli::Codex, &human).unwrap();
        assert!(dir.join("sessions").exists());
        assert!(dir.join("config.toml").exists());
        assert!(!dir.join("auth.json").exists());
    }

    #[test]
    fn agents_run_on_echos_login_only_while_it_is_signed_in() {
        let state = scratch("signin");
        // Nothing signed in to Echo: agents get the human's login, and nothing is set.
        let human = status(&state, Cli::Claude, &fake());
        assert!(!human.own);
        assert_eq!(human.account.as_deref(), Some("human@example.com"));
        assert!(env(&state).is_empty());

        let dir = dir(&state, Cli::Claude);
        std::fs::create_dir_all(&dir).unwrap();
        // What `claude auth login` leaves behind, in the fake.
        std::fs::write(dir.join("fake-login"), "").unwrap();
        let echo = status(&state, Cli::Claude, &fake());
        assert!(echo.own && echo.signed_in);
        assert_eq!(echo.account.as_deref(), Some("echo@example.com"));
        assert_eq!(
            env(&state),
            vec![("CLAUDE_CONFIG_DIR".to_string(), dir.display().to_string())]
        );

        sign_out(&state, Cli::Claude, &fake()).unwrap();
        assert!(!dir.join("fake-login").exists());
        assert!(env(&state).is_empty());
        assert!(!status(&state, Cli::Claude, &fake()).own);
    }

    #[test]
    fn kiro_is_read_but_never_signed_in_or_out_by_echo() {
        let state = scratch("kiro");
        let kiro = status(&state, Cli::Kiro, &fake());
        assert!(kiro.signed_in && !kiro.own);
        assert_eq!(kiro.account.as_deref(), Some("human@example.com"));
        assert!(login_args(Cli::Kiro).is_err());
        assert!(sign_out(&state, Cli::Kiro, &fake()).is_err());
        assert_eq!(kiro.view(Cli::Kiro)["shared"], json!(true));
    }

    #[test]
    fn a_cli_that_is_not_there_is_not_installed() {
        let state = scratch("missing");
        let missing = status(&state, Cli::Codex, "/nonexistent/codex");
        assert_eq!(missing, Status::default());
    }

    #[test]
    fn codexs_email_comes_from_its_id_token() {
        let root = scratch("email");
        let claims = B64.encode(r#"{"email":"echo@example.com"}"#);
        std::fs::write(
            root.join("auth.json"),
            format!(r#"{{"tokens":{{"id_token":"h.{claims}.s"}}}}"#),
        )
        .unwrap();
        assert_eq!(codex_email(&root).as_deref(), Some("echo@example.com"));
    }
}
