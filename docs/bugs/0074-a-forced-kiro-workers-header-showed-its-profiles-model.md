# A forced Kiro Worker's header showed its Profile's model instead of the one it ran

Found: 2026-11-13
Where: crates/hub/src/daemon.rs (`rows`), app/Sources/HubCore/Models.swift (`WorkerRow.modelLine`), app/Sources/HubApp/ContentView.swift (`WorkerHeader`)
Fixed in: the change that adds this file

Found by a smoke run of the Kiro parity work. With `forceCli` on and Kiro chosen, a Worker whose Profile says Sonnet, high effort ran Haiku on Kiro, and its header and the chat's model chip said Sonnet.
Cause: the row's `model` was the Worker's own explicit pick, else the Profile's model, and never went through `cli::pick`, which `spawn_for` uses and which puts the Profile's cli and model aside under `forceCli` (features/0075). No field named the CLI at all.
Fix: `rows` runs `cli::pick` for each Worker with the same inputs as `pick_for` (the settings files, the Profile's choice, the Worker's explicit pick), so `model` is what the CLI was started with, and adds `cli` to the row when it is not claude. The effort is still the Profile's: `profile::start` gives it to the CLI whatever the force, so it was right already. The header's Model line reads "kiro: claude-haiku-5.5, high effort" on another CLI. A Claude Worker's row has no `cli` key and the same `model` and `effort` as before, so its snapshot is unchanged and causes no redraw; a snapshot without `cli` still decodes. If the pick fails (a settings file that no longer reads), the row falls back to the old Profile-based values.
Limit: the row is computed from the settings as they are when the snapshot is built, not stored with the Worker, so changing `forceCli` while a Worker runs changes its header though not the CLI it is running on.
Lesson: show what was resolved, by the same function that resolved it at launch, not a copy of one input; and add a field to a snapshot only when it differs from the default, so an unchanged case stays byte for byte unchanged.
