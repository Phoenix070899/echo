//! Reading a Worker's screen: what Claude Code's, Codex's or Kiro's TUI is showing right now.

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

/// How many non-blank lines from the bottom a live dialog or spinner can be in; anything above
/// is transcript, where a quoted prompt or spinner must not count.
const RECENT: usize = 12;

/// Reads Claude Code's screen. Only the bottom counts: a dialog is live only
/// while no input box sits below it, and a spinner only just above the input box.
pub fn look(screen: &str) -> Look {
    let lines: Vec<&str> = screen.lines().map(str::trim).filter(|line| !line.is_empty()).collect();
    let recent = lines.len().saturating_sub(RECENT);
    // Ctrl+O's transcript view shows old prompts and spinners; the human is reading it.
    if lines[lines.len().saturating_sub(3)..]
        .iter()
        .any(|line| line.to_lowercase().contains("showing detailed transcript"))
    {
        return Look::Working;
    }
    let input = input_box(&lines);
    let live = |at: usize| at >= recent && input.is_none_or(|box_at| at > box_at);
    if lines
        .iter()
        .rposition(|line| line.contains("Yes, I trust this folder"))
        .is_some_and(live)
    {
        return Look::TrustPrompt;
    }
    if let Some(ask) = lines.iter().rposition(|line| line.starts_with("Do you want to")) {
        if live(ask) && lines[ask..].iter().any(|line| line.contains("1. Yes")) {
            return Look::PermissionPrompt;
        }
    }
    // The spinner sits in the few lines above the input box; without one, anywhere recent.
    let above = match input {
        Some(at) => &lines[at.saturating_sub(6).max(recent)..at],
        None => &lines[recent..],
    };
    let footer = input.map_or(&lines[..0], |at| &lines[at..]);
    if above.iter().any(|line| is_spinner(line)) || footer.iter().any(|line| line.contains("esc to interrupt")) {
        return Look::Working;
    }
    // Only the footer below the input box counts: the transcript keeps "1 shell still running" after it ends.
    if footer.iter().any(|line| line.split('·').any(is_background_count)) {
        return Look::Waiting;
    }
    Look::Idle
}

/// The input box: a `❯` line between two horizontal rules, the last one on screen.
fn input_box(lines: &[&str]) -> Option<usize> {
    (1..lines.len().saturating_sub(1))
        .rev()
        .find(|&at| lines[at].starts_with('❯') && lines[at - 1].starts_with('─') && lines[at + 1].starts_with('─'))
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

/// What a working Claude Code shows it is doing: its spinner line without the glyph, as in
/// `Nesting… (3s · ↓ 89 tokens)`, and the last `⏺` step above it, as in `Sleeping 8 seconds`.
pub fn activity(screen: &str) -> (Option<String>, Option<String>) {
    let lines: Vec<&str> = screen.lines().map(str::trim).filter(|line| !line.is_empty()).collect();
    let recent = lines.len().saturating_sub(RECENT);
    let Some(at) = lines[recent..]
        .iter()
        .rposition(|line| is_spinner(line))
        .map(|at| at + recent)
    else {
        return (None, None);
    };
    let spinner = lines[at].split_once(' ').map(|(_, rest)| rest.trim().to_string());
    let step = lines[..at]
        .iter()
        .rev()
        .take(RECENT)
        .find_map(|line| line.strip_prefix("⏺ "))
        .map(|step| step.trim().to_string());
    (spinner, step)
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

/// Kiro's screen, read the same way. Its screen is not bottom-anchored, so the lines are found by
/// content: the last `›` line is the input box, and `Kiro is working · 12s · Type to steer`
/// there means a turn is running. It has no footer for background work, so this never says
/// `Waiting`. A screen with no input box (a dialog, or Kiro not drawn yet) is `Working`: not at
/// its input, and nothing Echo should type into.
pub fn kiro_look(screen: &str) -> Look {
    let lines = kiro_lines(screen);
    if lines.is_empty() {
        return Look::Idle;
    }
    let recent = lines.len().saturating_sub(RECENT);
    let input = kiro_input(&lines);
    let live = |at: usize| at >= recent && input.is_none_or(|box_at| at > box_at);
    if let Some(at) = lines.iter().rposition(|line| line.contains("Trust, continue")) {
        let asked = lines[..at]
            .iter()
            .rev()
            .take(RECENT)
            .any(|line| line.starts_with("Trust this workspace?"));
        if live(at) && asked {
            return Look::TrustPrompt;
        }
    }
    if let Some(ask) = lines.iter().rposition(|line| line.ends_with("requires approval")) {
        // A long command wraps over many lines and pushes the title above the recent ones; the
        // dialog's own key hint as the last line of the screen still says it is the live one.
        let dialog = lines.last().is_some_and(|line| line.starts_with("esc to close")) && input.is_none_or(|b| ask > b);
        if (live(ask) || dialog) && lines[ask..].iter().any(|line| line.contains("Allow once")) {
            return Look::PermissionPrompt;
        }
    }
    let Some(at) = input.filter(|&at| at >= recent) else {
        return Look::Working;
    };
    let draft = lines[at].trim_start_matches('›').trim_start();
    if draft.starts_with("Kiro is working") || draft.starts_with("Initializing") {
        return Look::Working;
    }
    // Text typed into the box while a turn runs replaces its status; the activity line above the rule stays.
    let busy = kiro_footer_rule(&lines, at)
        .and_then(|rule| rule.checked_sub(1))
        .is_some_and(|above| lines[above] == "esc to cancel" || lines[above].ends_with("(esc to cancel)"));
    if busy {
        Look::Working
    } else {
        Look::Idle
    }
}

/// Kiro's non-blank lines, trimmed.
fn kiro_lines(screen: &str) -> Vec<&str> {
    screen.lines().map(str::trim).filter(|line| !line.is_empty()).collect()
}

/// Kiro's input box: the last line that starts with `›`.
fn kiro_input(lines: &[&str]) -> Option<usize> {
    lines.iter().rposition(|line| line.starts_with('›'))
}

/// The horizontal rule above Kiro's status line and input box: the nearest one, a few lines up.
fn kiro_footer_rule(lines: &[&str], input: usize) -> Option<usize> {
    lines[..input]
        .iter()
        .rposition(|line| line.starts_with('─'))
        .filter(|rule| input - rule <= 3)
}

/// Kiro's approval: its title line (`<what> requires approval`) and what it asks about
/// (`shell → touch y`), up to the first option.
pub fn kiro_prompt_lines(screen: &str) -> String {
    let lines = kiro_lines(screen);
    let Some(ask) = lines.iter().rposition(|line| line.ends_with("requires approval")) else {
        return String::new();
    };
    let end = lines[ask..]
        .iter()
        .position(|line| line.contains("Allow once"))
        .map_or(lines.len(), |at| ask + at);
    lines[ask..end].join("\n")
}

/// A Kiro turn that finished at its input box: the `▸ Credits: turn 0.00 | Time: 4s` line
/// sits right above the rule over the status line. A cancelled or failed turn prints no credits.
pub fn kiro_turn_ended(screen: &str) -> bool {
    if kiro_look(screen) != Look::Idle {
        return false;
    }
    let lines = kiro_lines(screen);
    kiro_input(&lines)
        .and_then(|input| kiro_footer_rule(&lines, input))
        .and_then(|rule| rule.checked_sub(1))
        .is_some_and(|above| lines[above].starts_with("▸ Credits:"))
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
    fn an_old_prompt_in_the_transcript_is_not_live() {
        let screen = "Bash command\n rm -rf junk\nDo you want to proceed?\n❯ 1. Yes\n  2. No\n⏺ Removed junk.\n\
                      ✻ Brewed for 3s · done 4:38 PM\n────\n❯ \n────\n  ⏵⏵ auto mode on";
        assert_eq!(look(screen), Look::Idle);
    }

    #[test]
    fn a_trust_dialog_quoted_in_the_transcript_is_not_live() {
        let screen = "⏺ The dialog says \"Yes, I trust this folder\".\n────\n❯ \n────\n  ⏵⏵ auto mode on";
        assert_eq!(look(screen), Look::Idle);
    }

    #[test]
    fn a_spinner_quoted_far_above_the_input_box_is_not_working() {
        let mut screen = String::from("⏺ The spinner reads · Churning… (21s · ↓ 81 tokens)\n");
        for n in 0..8 {
            screen += &format!("  line {n}\n");
        }
        screen += "✻ Brewed for 3s · done 4:38 PM\n────\n❯ \n────\n  ⏵⏵ auto mode on";
        assert_eq!(look(&screen), Look::Idle);
    }

    #[test]
    fn esc_to_interrupt_in_the_footer_is_working() {
        let screen = "⏺ Reading files\n────\n❯ \n────\n  ⏵⏵ auto mode on · esc to interrupt";
        assert_eq!(look(screen), Look::Working);
    }

    /// Claude Code 2.1.308's screens, captured from a real session.
    const REAL_PROMPT: &str = "  ⎿  $ touch made-by-test.txt\n────────────────\n Bash command\n Create made-by-test.txt\n\
                               ╌╌╌╌\n touch made-by-test.txt\n╌╌╌╌\n Do you want to proceed?\n ❯ 1. Yes\n   2. Yes, and always allow\n\
                               3. Yes, and switch to auto mode\n   4. No\n Esc to cancel · Tab to amend";
    const REAL_WORKING: &str = "❯ Run the bash command: sleep 8 && echo hi\n⏺ Sleeping 8 seconds then echo hi\n  ⎿  $ sleep 8 && echo hi\n\
                                ✶ Nesting… (3s · ↓ 89 tokens)\n                    ◐ medium · /effort\n────────────────\n❯ \n\
                                ────────────────\n    Haiku 5.5 | ctx: 5% used\n  ⏵⏵ auto mode on (shift+tab to cycle) · ← 2 agents";

    #[test]
    fn reads_real_claude_screens() {
        assert_eq!(look(REAL_PROMPT), Look::PermissionPrompt);
        assert_eq!(look(REAL_WORKING), Look::Working);
        let finished = REAL_WORKING.replace("✶ Nesting… (3s · ↓ 89 tokens)", "✻ Brewed for 9s · done 4:38 PM");
        assert_eq!(look(&finished), Look::Idle);
        // The prompt answered: it scrolls into the transcript and the input box comes back below it.
        let answered = format!("{REAL_PROMPT}\n⏺ Done.\n────────────────\n❯ \n────────────────\n  ⏵⏵ auto mode on");
        assert_eq!(look(&answered), Look::Idle);
    }

    #[test]
    fn activity_is_the_spinner_and_the_step_above_it() {
        assert_eq!(
            activity(REAL_WORKING),
            (
                Some("Nesting… (3s · ↓ 89 tokens)".into()),
                Some("Sleeping 8 seconds then echo hi".into())
            )
        );
        let finished = REAL_WORKING.replace("✶ Nesting… (3s · ↓ 89 tokens)", "✻ Brewed for 9s · done 4:38 PM");
        assert_eq!(activity(&finished), (None, None));
    }

    #[test]
    fn the_transcript_view_is_never_a_prompt() {
        let screen = "Do you want to proceed?\n❯ 1. Yes\n  2. No\n  Showing detailed transcript · ctrl+o to toggle";
        assert_eq!(look(screen), Look::Working);
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

    /// Kiro CLI 3.2.1's screens, captured from a real session (docs/research/kiro-cli-spike.md).
    const KIRO_IDLE: &str = include_str!("../tests/fixtures/kiro/idle.txt");
    const KIRO_WORKING: &str = include_str!("../tests/fixtures/kiro/working.txt");
    const KIRO_WORKING_SHELL: &str = include_str!("../tests/fixtures/kiro/working-shell.txt");
    const KIRO_WORKING_TEXT: &str = include_str!("../tests/fixtures/kiro/working-text.txt");
    const KIRO_DONE: &str = include_str!("../tests/fixtures/kiro/done.txt");
    const KIRO_PERMISSION: &str = include_str!("../tests/fixtures/kiro/permission.txt");
    const KIRO_PERMISSION_FSREAD: &str = include_str!("../tests/fixtures/kiro/permission-fsread.txt");
    const KIRO_PERMISSION_FSWRITE: &str = include_str!("../tests/fixtures/kiro/permission-fswrite.txt");
    const KIRO_PERMISSION_ALWAYS: &str = include_str!("../tests/fixtures/kiro/permission-always.txt");
    const KIRO_ALLOWED_ONCE: &str = include_str!("../tests/fixtures/kiro/allowed-once.txt");
    const KIRO_REJECTED: &str = include_str!("../tests/fixtures/kiro/rejected.txt");
    const KIRO_DENIED_BY_RULE: &str = include_str!("../tests/fixtures/kiro/denied-by-rule.txt");
    const KIRO_CANCELLED: &str = include_str!("../tests/fixtures/kiro/cancelled.txt");
    const KIRO_CANCELLED_TOOL: &str = include_str!("../tests/fixtures/kiro/cancelled-tool.txt");
    const KIRO_TRUST: &str = include_str!("../tests/fixtures/kiro/trust.txt");
    const KIRO_WAITING: &str = include_str!("../tests/fixtures/kiro/waiting.txt");
    const KIRO_USAGE: &str = include_str!("../tests/fixtures/kiro/usage.txt");
    const KIRO_UNKNOWN_MODEL: &str = include_str!("../tests/fixtures/kiro/unknown-model.txt");
    const KIRO_RESUMED: &str = include_str!("../tests/fixtures/kiro/resumed.txt");

    /// Kiro's rule, status line and idle input box, as the bottom of every captured idle screen.
    const KIRO_IDLE_BOTTOM: &str =
        "────────\necho-spike-a · claude-haiku-5.5 · thinking · medium · ◔ 1%    /tmp/r · (main)\n\
                                    ›  ask a question or describe a task ↵\n";

    #[test]
    fn reads_kiro_at_its_input_box() {
        assert_eq!(kiro_look(KIRO_IDLE), Look::Idle);
        assert_eq!(kiro_look(KIRO_DONE), Look::Idle);
        assert_eq!(kiro_look(KIRO_ALLOWED_ONCE), Look::Idle);
        assert_eq!(kiro_look(KIRO_UNKNOWN_MODEL), Look::Idle);
        assert_eq!(kiro_look(KIRO_RESUMED), Look::Idle);
        assert_eq!(kiro_look(""), Look::Idle);
    }

    #[test]
    fn reads_kiro_working() {
        assert_eq!(kiro_look(KIRO_WORKING), Look::Working);
        assert_eq!(kiro_look(KIRO_WORKING_SHELL), Look::Working);
        assert_eq!(kiro_look(KIRO_WORKING_TEXT), Look::Working);
    }

    #[test]
    fn kiro_loading_is_not_ready_for_typing() {
        let loading = KIRO_IDLE.replace(
            "ask a question or describe a task ↵",
            "Initializing · type to queue a message",
        );
        assert_eq!(kiro_look(&loading), Look::Working);
    }

    #[test]
    fn reads_kiro_permission_prompts() {
        assert_eq!(kiro_look(KIRO_PERMISSION), Look::PermissionPrompt);
        assert_eq!(kiro_look(KIRO_PERMISSION_FSREAD), Look::PermissionPrompt);
        assert_eq!(kiro_look(KIRO_PERMISSION_FSWRITE), Look::PermissionPrompt);
    }

    #[test]
    fn reads_kiro_trust_dialog() {
        assert_eq!(kiro_look(KIRO_TRUST), Look::TrustPrompt);
    }

    #[test]
    fn kiro_never_waits_on_background_work() {
        // Q8: a background command leaves the normal idle screen, with no footer for it.
        assert_eq!(kiro_look(KIRO_WAITING), Look::Idle);
    }

    #[test]
    fn a_cancelled_kiro_turn_is_idle() {
        assert_eq!(kiro_look(KIRO_CANCELLED), Look::Idle);
        assert_eq!(kiro_look(KIRO_CANCELLED_TOOL), Look::Idle);
    }

    #[test]
    fn an_answered_or_blocked_kiro_prompt_is_idle() {
        assert_eq!(kiro_look(KIRO_REJECTED), Look::Idle);
        assert_eq!(kiro_look(KIRO_DENIED_BY_RULE), Look::Idle);
    }

    #[test]
    fn kiro_dialogs_without_an_input_box_are_not_idle_or_decidable() {
        // The "always" rule dialog and /usage have no approve-once row, so deciding them would misfire.
        assert_eq!(kiro_look(KIRO_PERMISSION_ALWAYS), Look::Working);
        assert_eq!(kiro_look(KIRO_USAGE), Look::Working);
    }

    #[test]
    fn an_old_kiro_permission_prompt_in_the_transcript_is_not_live() {
        let lines: Vec<&str> = KIRO_PERMISSION.lines().collect();
        let from = lines
            .iter()
            .position(|line| line.ends_with("requires approval"))
            .unwrap();
        let quoted = lines[from..].join("\n");
        let screen = format!("{quoted}\n• Shell touch y\n▸ Credits: turn 0.00 | Time: 4s\n{KIRO_IDLE_BOTTOM}");
        assert_eq!(kiro_look(&screen), Look::Idle);
        // Far above the bottom, with no input box on screen at all, it is still not live.
        let mut far = String::from(quoted.as_str());
        for n in 0..14 {
            far += &format!("\n  line {n}");
        }
        assert_eq!(kiro_look(&far), Look::Working);
    }

    #[test]
    fn a_kiro_permission_prompt_for_a_long_wrapped_command_is_live() {
        // A command of 7 screen lines puts the title 14 lines above the bottom, past RECENT.
        let long = (0..7)
            .map(|n| format!(" segment{n:03} segment{n:03} segment{n:03}"))
            .collect::<Vec<_>>()
            .join("\n");
        let screen = KIRO_PERMISSION.replace(" shell → touch y", &format!(" shell → echo\n{long}"));
        assert_eq!(kiro_look(&screen), Look::PermissionPrompt);
        assert!(kiro_prompt_lines(&screen).contains("segment006"));
        // The same lines quoted in the transcript, with the idle box below, are not live.
        let quoted = format!("{}\n{KIRO_IDLE_BOTTOM}", screen.trim_end());
        assert_eq!(kiro_look(&quoted), Look::Idle);
    }

    #[test]
    fn a_kiro_trust_dialog_quoted_in_the_transcript_is_not_live() {
        let screen = format!("• The dialog reads Trust this workspace? then ❯ Trust, continue\n{KIRO_IDLE_BOTTOM}");
        assert_eq!(kiro_look(&screen), Look::Idle);
        let lines: Vec<&str> = KIRO_TRUST.lines().collect();
        let from = lines
            .iter()
            .position(|line| line.contains("Trust this workspace?"))
            .unwrap();
        let quoted = lines[from..].join("\n");
        assert_eq!(kiro_look(&quoted), Look::TrustPrompt);
        assert_eq!(kiro_look(&format!("{quoted}\n{KIRO_IDLE_BOTTOM}")), Look::Idle);
    }

    #[test]
    fn a_working_line_quoted_in_the_kiro_transcript_is_not_working() {
        let screen = format!(
            "• The box reads:\n› Kiro is working · 1s · Type to steer · Ctrl+S to queue\n\
             • Thinking... (esc to cancel)\n▸ Credits: turn 0.00 | Time: 4s\n{KIRO_IDLE_BOTTOM}"
        );
        assert_eq!(kiro_look(&screen), Look::Idle);
    }

    #[test]
    fn kiro_text_typed_while_it_works_is_still_working() {
        let steering = KIRO_WORKING.replace(
            "Kiro is working · 1s · Type to steer · Ctrl+S to queue",
            "try it another way",
        );
        assert!(steering.contains("› try it another way") || steering.contains("›  try it another way"));
        assert_eq!(kiro_look(&steering), Look::Working);
        let tool = KIRO_WORKING_SHELL.replace("Kiro is working · 6s · Type to steer · Ctrl+S to queue", "stop it");
        assert_eq!(kiro_look(&tool), Look::Working);
        // A draft typed at an idle box is not a running turn.
        let draft = KIRO_DONE.replace("ask a question or describe a task ↵", "fix the build");
        assert_eq!(kiro_look(&draft), Look::Idle);
    }

    #[test]
    fn kiro_prompt_lines_are_the_title_and_what_it_asks_about() {
        assert_eq!(
            kiro_prompt_lines(KIRO_PERMISSION),
            "Create empty file named y requires approval\nshell → touch y"
        );
        assert_eq!(
            kiro_prompt_lines(KIRO_PERMISSION_FSREAD),
            "Create empty file named y requires approval\nfs_read → ."
        );
        assert_eq!(
            kiro_prompt_lines(KIRO_PERMISSION_FSWRITE),
            "Write File requires approval\nfs_write → /private/tmp/kirospike-outside/x.txt"
        );
        assert_eq!(kiro_prompt_lines(KIRO_IDLE), "");
    }

    #[test]
    fn a_kiro_turn_ended_at_the_input_box() {
        assert!(kiro_turn_ended(KIRO_DONE));
        assert!(kiro_turn_ended(KIRO_ALLOWED_ONCE));
        assert!(kiro_turn_ended(KIRO_DENIED_BY_RULE));
        assert!(!kiro_turn_ended(KIRO_WORKING));
        assert!(!kiro_turn_ended(KIRO_WORKING_TEXT));
        assert!(!kiro_turn_ended(KIRO_PERMISSION));
        assert!(!kiro_turn_ended(KIRO_IDLE), "nothing has run yet");
        assert!(!kiro_turn_ended(KIRO_RESUMED), "the last turn there was cancelled");
        assert!(!kiro_turn_ended(KIRO_CANCELLED));
        assert!(!kiro_turn_ended(KIRO_CANCELLED_TOOL));
        assert!(!kiro_turn_ended(KIRO_UNKNOWN_MODEL), "a failed turn prints no credits");
        assert!(!kiro_turn_ended(""));
    }

    #[test]
    fn credits_quoted_in_the_kiro_transcript_do_not_end_a_turn() {
        let screen =
            format!("• Last turn:\n▸ Credits: turn 0.00 | Time: 4s\n• I am still reading.\n{KIRO_IDLE_BOTTOM}");
        assert!(!kiro_turn_ended(&screen));
    }
}
