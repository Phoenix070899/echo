# An Orchestrator took Claude Code's prompt suggestion for typed text

Found: 2026-11-18
Where: settings/worker.json

In a benchmark run, an Orchestrator read a Worker's screen, saw "push it" in its prompt, decided someone had typed it, and closed the Worker so it could not be sent.
Cause: Claude Code shows a greyed suggested next prompt in an idle prompt box, and a screen read cannot tell it from typed text.
Fix: Workers run with `"promptSuggestionEnabled": false`.
Lesson: what an agent reads off a Worker's screen must hold only what is really there; turn off any CLI feature that draws text into the prompt.
