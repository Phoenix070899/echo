# Task specs say where to start reading, and Workers read each file once

Decided: 2026-10-31
Status: accepted

Every Task spec ends with "Start from": the files and line ranges the Orchestrator read while planning, each with one line on what it holds.
The Worker Contract tells a Worker to begin there and search only for what they miss, to read each file once and again only after it changed, and to read files with the Read tool rather than `cat`, `head`, or `sed`.
Why: over two weeks (670 Workers) each Worker made about 11 reads and searches (1.5 Read calls, 4.8 `cat`, `head`, or `sed`, 4.5 searches) mostly redoing what its Orchestrator had read while planning; only 1 to 2% of Read calls repeated a file, so the read-once line is a guard, not the main gain.
Rejected: replacing graft with another code-search tool, because searching is the smaller share and Workers barely used graft (32 calls).
