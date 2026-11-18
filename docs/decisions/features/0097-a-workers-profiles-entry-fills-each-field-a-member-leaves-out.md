# A moved `workers.profiles` entry fills each field a Member leaves out

Decided: 2026-11-15
Status: accepted

Builds on features/0095; it narrows its "each Member of that Profile that sets none of the three fields".
When the daemon moves a `workers.profiles.<Profile>` entry, each Member of that Profile takes the entry's `cli`, `model` and `effort` for every one of the three it does not set itself; a Member that sets all three takes nothing.
An entry no Member of the Team starts from is dropped, and the daemon logs that it was.
Why: features/0085 ordered the Member over the entry field by field, so a Member that set only its effort ran on the entry's model; moving the entry onto Members that set none would change that Worker's model without a word, which features/0095 forbids.
Rejected: moving the entry only onto Members that set none of the three, which changes how such a Worker runs.
