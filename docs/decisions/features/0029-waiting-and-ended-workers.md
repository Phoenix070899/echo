# A Worker on background work is Waiting; one that stops without a report is Ended

Decided: 2026-10-24
Status: accepted

A live Worker at its input box while background work it started still runs is Waiting, not Needs you.
The screen says so in the footer below the input box: a count of shells, monitors, agents, or tasks, alone or in a list, as in `· 1 shell, 1 monitor ·`; the agents pill (`← 2 agents`) is not one.
Waiting is a Dashboard state (`waiting`); it sorts and counts with running, and its lifecycle phase stays `running`.
A Worker that finished its turn at the input box (`✻ … for 18s · done` above `❯`) and then exits or is closed with no Final Report settles as `ended`, not `exited`.
Its last screen, in a code block, is kept as its Final Report; it is not trouble, so it shows in Done with a grey mark and "Ended, no Final Report".
Exiting mid-turn, or before the turn started, is still `exited` (Failed).
Ended Workers resume like exited ones, and the Orchestrator still gets an `exited` message whose body says "ended"; orchestrator.md tells it to check that screen against the acceptance.
Why: bash Workers on Haiku often print their report and skip `hub done`, so the Orchestrator closes them and they read as Failed; and a Worker watching a Monitor read as idle and was raised as Needs you.
