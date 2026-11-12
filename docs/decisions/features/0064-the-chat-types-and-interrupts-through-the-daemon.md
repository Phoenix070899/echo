# The chat types through `chat.send`, which refuses over a prompt, and interrupts with `chat.interrupt`

Decided: 2026-11-12
Status: accepted

`chat.send` (agent, text) types the text at a running agent's input box as one paste, then Enter, and names a still-unnamed agent from its first line, as `terminal.send` does.
It refuses while the agent shows a permission prompt or the folder-trust dialog, so text cannot answer it (features/0045); there is no force.
`chat.interrupt` sends one Esc to the agent.
`chat.read` also returns the terminal's `state`: `live`, `look` (stopped, trust, prompt, working, waiting, idle), and while working the spinner line and the last `⏺` step (`screen::activity`).
Why: the chat must never type an answer into a prompt the human did not see; Approve and Deny settle prompts.
