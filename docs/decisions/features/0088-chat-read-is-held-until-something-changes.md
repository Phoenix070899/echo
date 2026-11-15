# A shown chat's `chat.read` is held by the daemon until something it shows changes

Decided: 2026-11-15
Status: accepted

`chat.read` takes `wait` (milliseconds, 15 s at most) and `state`, the Working state Echo shows; with them, a read that has nothing new is held until the transcript grows, the session changes, or the Working state is no longer `state`.
A held read wakes on its terminal's output and looks at the transcript's size and the screen then, and reads again in full every second whatever the terminal does, for a line written with no output or an agent that started meanwhile.
A held read that only has a new Working state answers no sooner than 100 ms after it began, so the Working row redraws ten times a second at most.
Echo's shown chat reads in a loop: its first read answers at once, every later one is held, and a read that changed nothing is followed by 100 ms of rest; hiding the chat closes the read in flight.
A page back (`before`) is never held, and Echo Remote keeps its own wait.
Why: Echo polled every 800 ms, so a finished message or a step showed up to 800 ms late and the Working row moved in jumps; a held read shows both within a few ms.
Rejected: pushing chat items on the `events` stream, which Echo would have to merge with paging back; polling faster, which costs a call ten times a second per shown chat and still lags; a kqueue watch on the transcript, which is macOS-only and has to follow each new session's file.
