//! Reading a Worker's screen: what Claude Code's or Codex's TUI is showing right now.

/// What a Worker's screen says about it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Look {
    /// Claude's "trust this folder?" dialog, shown once per new folder.
    TrustPrompt,
    /// A tool permission prompt ("Do you want to proceed?" with numbered choices).
    PermissionPrompt,
    /// A turn is running: the spinner line, e.g. `· Churning… (21s · ↓ 81 tokens)`.
    Working,
    /// At its input box while background work it started still runs: the footer counts it, as in
    /// `· 1 shell ·`, `· 1 monitor ·`, or `· 1 shell, 1 monitor ·`.
    Waiting,
    /// Waiting at its input box.
    Idle,
}

pub fn look(screen: &str) -> Look {
    if screen.contains("Yes, I trust this folder") {
        return Look::TrustPrompt;
    }
    let lines: Vec<&str> = screen.lines().map(str::trim).collect();
    let asks = lines.iter().any(|line| line.starts_with("Do you want to"));
    let choices = lines.iter().any(|line| line.contains("1. Yes"));
    if asks && choices {
        return Look::PermissionPrompt;
    }
    if lines.iter().any(|line| is_spinner(line)) {
        return Look::Working;
    }
    // Only the footer below the input box counts: the transcript keeps "1 shell still running" after it ends.
    let footer = lines
        .iter()
        .rposition(|line| line.starts_with('❯'))
        .map_or(&lines[..0], |at| &lines[at..]);
    if footer.iter().any(|line| line.split('·').any(is_background_count)) {
        return Look::Waiting;
    }
    Look::Idle
}

/// Whether the screen shows a turn that finished at the input box, as in
/// `✻ Brewed for 18s · done 4:38 PM` above an empty `❯`: the Worker stopped on its own.
pub fn turn_ended(screen: &str) -> bool {
    let lines: Vec<&str> = screen.lines().map(str::trim).collect();
    let finished = lines
        .iter()
        .any(|line| line.starts_with('✻') && line.contains(" for ") && line.contains("· done"));
    finished && lines.iter().any(|line| line.starts_with('❯')) && matches!(look(screen), Look::Idle | Look::Waiting)
}

/// A footer segment counting background work, like "1 shell", "2 shells", "1 monitor", or
/// "1 shell, 1 monitor". The agents pill ("← 2 agents") is not one.
fn is_background_count(segment: &str) -> bool {
    segment.split(',').all(|part| {
        let mut words = part.split_whitespace();
        let count = words.next().is_some_and(|n| n.parse::<u32>().is_ok_and(|n| n > 0));
        let noun = matches!(
            words.next(),
            Some("shell" | "shells" | "monitor" | "monitors" | "agent" | "agents" | "task" | "tasks")
        );
        count && noun && words.next().is_none()
    })
}

/// The spinner line: a glyph, a word ending in "…", then "(<digits>".
fn is_spinner(line: &str) -> bool {
    let Some(at) = line.find("… (") else {
        return false;
    };
    let after = &line[at + "… (".len()..];
    let glyph_word = line.split_whitespace().count() >= 2 && !line.starts_with('❯');
    glyph_word && after.chars().next().is_some_and(|c| c.is_ascii_digit())
}

/// The permission prompt's own lines: what is asked about, up to "Do you want to ...".
pub fn prompt_lines(screen: &str) -> String {
    let lines: Vec<&str> = screen.lines().map(str::trim).collect();
    let Some(ask) = lines.iter().rposition(|line| line.starts_with("Do you want to")) else {
        return String::new();
    };
    let start = lines[..ask]
        .iter()
        .rposition(|line| line.starts_with('─'))
        .map_or(0, |at| at + 1);
    lines[start..=ask]
        .iter()
        .filter(|line| !line.is_empty() && !line.starts_with('╌'))
        .copied()
        .collect::<Vec<_>>()
        .join("\n")
}

/// Codex's screen, read the same way: its trust dialog, its command approval, its
/// `• Working (10s • esc to interrupt)` line, or its `› Ask Codex to do anything` box.
pub fn codex_look(screen: &str) -> Look {
    let lines: Vec<&str> = screen.lines().map(str::trim).collect();
    if lines.iter().any(|line| line.contains("Trust this folder?")) && screen.contains("Trust and continue") {
        return Look::TrustPrompt;
    }
    if lines
        .iter()
        .any(|line| line.starts_with("Press enter to confirm or esc to cancel"))
        && lines.iter().any(|line| line.contains("1. Yes"))
    {
        return Look::PermissionPrompt;
    }
    if lines.iter().any(|line| line.contains("esc to interrupt")) {
        return Look::Working;
    }
    // At its input box while a command it started runs on: "· 1 background terminal running ·".
    if lines
        .iter()
        .any(|line| line.contains("background terminal running") || line.contains("background terminals running"))
    {
        return Look::Waiting;
    }
    Look::Idle
}

/// Codex's approval: from "Would you like to ..." to the command it asks about.
pub fn codex_prompt_lines(screen: &str) -> String {
    let lines: Vec<&str> = screen.lines().map(str::trim).collect();
    let Some(ask) = lines.iter().rposition(|line| line.starts_with("Would you like to")) else {
        return String::new();
    };
    let end = lines[ask..]
        .iter()
        .position(|line| line.starts_with("1. ") || line.starts_with("› 1."))
        .map_or(lines.len(), |at| ask + at);
    lines[ask..end]
        .iter()
        .filter(|line| !line.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join("\n")
}

/// A Codex turn that finished at its input box: it answered (`• ...`) and works no more.
pub fn codex_turn_ended(screen: &str) -> bool {
    codex_look(screen) == Look::Idle
        && screen.lines().any(|line| line.trim_start().starts_with("• "))
        && screen.lines().any(|line| line.trim_start().starts_with("› "))
}

/// The last `count` non-blank lines, right-trimmed.
pub fn tail(screen: &str, count: usize) -> String {
    let lines: Vec<&str> = screen
        .lines()
        .map(str::trim_end)
        .filter(|line| !line.is_empty())
        .collect();
    lines[lines.len().saturating_sub(count)..].join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_trust_dialog() {
        let screen = " Quick safety check\n ❯ No, exit\n   Yes, I trust this folder\n Enter to confirm";
        assert_eq!(look(screen), Look::TrustPrompt);
    }

    #[test]
    fn reads_a_permission_prompt() {
        let screen = "Bash command\n  rm -rf build\nDo you want to proceed?\n❯ 1. Yes\n  2. No, and tell Claude";
        assert_eq!(look(screen), Look::PermissionPrompt);
    }

    #[test]
    fn reads_the_spinner_as_working() {
        let screen = "❯ Run it\n⏺ Sleeping 20 seconds · 17s\n· Churning… (21s · ↓ 81 tokens)\n────\n❯ \n────";
        assert_eq!(look(screen), Look::Working);
    }

    #[test]
    fn a_finished_turn_is_idle() {
        let screen = "⏺ DONE\n✻ Cogitated for 17s · done 5:29 PM\n────\n❯ \n────\n  Haiku 5.5";
        assert_eq!(look(screen), Look::Idle);
    }

    #[test]
    fn idle_with_a_background_shell_is_waiting() {
        let screen = "⏺ Step B runs in the background.\n✻ Baked for 12s · done 11:00 AM · 1 shell still running\n\
                      ────\n❯ \n────\n    Haiku 5.5 | ctx: 59% used\n  ⏵⏵ auto mode on · 2 shells · ← 1 agent";
        assert_eq!(look(screen), Look::Waiting);
    }

    #[test]
    fn idle_with_a_monitor_is_waiting() {
        // Claude Code 2.1.308's footers, with a Monitor alone and beside a background shell.
        for footer in [
            "⏵⏵ auto mode on · 1 monitor · ← 2 agents",
            "⏵⏵ auto mode on · 1 shell, 1 monitor · ← 2 agents",
        ] {
            let screen =
                format!("✻ Baked for 2s · done 11:45 PM · 1 monitor still running\n────\n❯ \n────\n  {footer}");
            assert_eq!(look(&screen), Look::Waiting, "{footer}");
        }
    }

    #[test]
    fn the_agents_pill_is_not_background_work() {
        assert_eq!(
            look("✻ Baked for 2s · done 11:45 PM\n────\n❯ \n────\n  ⏵⏵ auto mode on · ← 2 agents"),
            Look::Idle
        );
    }

    #[test]
    fn a_turn_ended_at_the_input_box() {
        let screen =
            "⏺ Done. Both databases are dropped.\n✻ Brewed for 18s · done 4:38 PM\n────\n❯ \n────\n    Haiku 5.5";
        assert!(turn_ended(screen));
        assert!(!turn_ended(
            "⏺ Running it\n· Churning… (21s · ↓ 81 tokens)\n────\n❯ \n────"
        ));
        assert!(!turn_ended(""));
    }

    #[test]
    fn a_finished_background_shell_in_the_transcript_is_idle() {
        let screen =
            "✻ Baked for 12s · done 11:00 AM · 1 shell still running\n────\n❯ \n────\n  ⏵⏵ auto mode on · ← 1 agent";
        assert_eq!(look(screen), Look::Idle);
    }

    #[test]
    fn typed_ellipsis_in_the_prompt_is_not_a_spinner() {
        assert_eq!(look("❯ wait… (1 more thing)"), Look::Idle);
    }

    #[test]
    fn prompt_lines_are_the_box_above_the_question() {
        let screen = "⏺ Running…\n────────\n Bash command\n Remove junk\n╌╌╌╌\n rm -rf junk\n╌╌╌╌\n Do you want to proceed?\n ❯ 1. Yes";
        assert_eq!(
            prompt_lines(screen),
            "Bash command\nRemove junk\nrm -rf junk\nDo you want to proceed?"
        );
    }

    #[test]
    fn tail_keeps_the_last_non_blank_lines() {
        assert_eq!(tail("a\n\nb  \nc\n\n", 2), "b\nc");
    }

    const CODEX_TRUST: &str = "  Folder access\n  /private/tmp/r\n  Trust this folder? Codex can read, edit, and run files here.\n› 1. Trust and continue\n  2. Quit\n  enter continue · esc quit\n";
    const CODEX_ASK: &str = "› Run exactly: touch /x\n• Running touch /x\n  Would you like to run the following command?\n  Environment: local\n  Reason: Do you want to allow creating the file?\n  $ touch /x\n› 1. Yes, proceed (y)\n  2. Yes, and don't ask again (p)\n  3. No, and tell Codex what to do differently (esc)\n  Press enter to confirm or esc to cancel\n";
    const CODEX_WORKING: &str = "› Run exactly: ls\n• Ran ls\n  └ README.md\n• Working (10s • esc to interrupt)\n› Ask Codex to do anything\n  ? for shortcuts\n";
    const CODEX_DONE: &str = "› Run exactly: ls\n• Ran ls\n  └ README.md\n• Listed: README.md\n  11:58\n› Ask Codex to do anything\n  GPT-5.6-Terra low · /private/tmp/r\n  ? for shortcuts\n";

    #[test]
    fn reads_codex_screens() {
        assert_eq!(codex_look(CODEX_TRUST), Look::TrustPrompt);
        assert_eq!(codex_look(CODEX_ASK), Look::PermissionPrompt);
        assert_eq!(codex_look(CODEX_WORKING), Look::Working);
        assert_eq!(codex_look(CODEX_DONE), Look::Idle);
        assert!(codex_turn_ended(CODEX_DONE));
        let waiting = CODEX_DONE.replace("  ? for shortcuts", "  1 background terminal running · /ps to view");
        assert_eq!(codex_look(&waiting), Look::Waiting);
        assert!(!codex_turn_ended(CODEX_WORKING));
        assert_eq!(
            codex_prompt_lines(CODEX_ASK),
            "Would you like to run the following command?\nEnvironment: local\nReason: Do you want to allow creating the file?\n$ touch /x"
        );
        assert_eq!(
            look(CODEX_ASK),
            Look::Idle,
            "Claude's reader does not take Codex's prompt for its own"
        );
    }
}
