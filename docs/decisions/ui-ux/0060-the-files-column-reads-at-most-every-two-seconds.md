# While an agent keeps writing, the Files column reads its checkout at most every two seconds

Decided: 2026-11-02
Status: accepted

Supersedes: ui-ux/0016's "reads the checkout again within about half a second of any change", and the same words in features/0020.
A change after a quiet spell still reads the checkout within about half a second.
While changes keep coming, the next read waits until 2 s after the last one began, and changes meanwhile wait for it; an open preview of a changed file follows the same reads.
Why: an agent at work writes many times a second, and each read runs three or four git commands and lays the tree out again; a file written ten times a second kept the main thread busy for about 320 ms of every 9 s, and about 115 to 180 ms with the gap (`FILES=1 WRITES=1 app/scripts/measure-switch.sh`). Orca waits at least 3 s between reads.
