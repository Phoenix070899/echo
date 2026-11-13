# Kiro credits round to the nearest percent

Decided: 2026-11-13
Status: accepted

Supersedes: features/0078, only its words "floored as Kiro's own figure is".
The `percent` of the "Kiro credits" entry is the used share of the plan's credits rounded to the nearest whole number (580 of 2000 is 29), as the code has done since the fix in bugs/0073; `detail` stays as 0078 says.
Why: flooring showed one point less than the share is whenever the fraction was half or more, and Kiro's own TUI figure is not a rule Echo must copy.
