# A new chat row fades in, as a Worker row does

Decided: 2026-11-15
Status: accepted

A row added below the ones a chat shows fades in over 0.15 s (ease out), as Worker rows do (ui-ux/0014); the bottom anchor keeps it in sight.
A chat's first read, a new session, and a page back show their rows at once.
Under Reduce Motion a new row shows at once.
Why: with the held read (features/0088) rows arrive as they are written, and popping in one by one read as flicker.
