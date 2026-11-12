# A Ledger row's Worker id column is 40 pt wide

Decided: 2026-11-12
Status: accepted

The Worker id in a Ledger row (`LedgerRow`) gets a 40 pt column on one line; it was 32 pt.
Why: after the restyle a four-digit id such as w1009 wrapped to "w100" over "9" and pushed the row's height up; 40 pt fits five monospaced characters at 11.5 pt.
Rejected: shrinking the id's font, which is already the smallest in the row.
