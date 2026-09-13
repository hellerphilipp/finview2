# Transfers

Money moved between your own accounts shouldn't count as spending. Tally lets
you mark these as transfers so they're excluded from spending totals and
reports — e.g. −2'000 CHF on Current ↔ +2'000 CHF on Savings.

Transfers are handled inside the **Transactions** view (there's no separate
screen); a linked pair is marked in the list with a ↔ glyph, and the glyph's
tooltip names the account on the other side.

## Linking a pair by hand

Select two transactions, right-click, and choose **Link as Transfer**. The
command only appears when the selection is a valid pair:

- **exactly 2 rows**,
- on **different accounts**,
- in the **same currency**, and
- with **equal-and-opposite amounts** (one −X, the other +X).

Right-clicking a row that's already linked offers **Unlink Transfer**, which
removes the link from both sides.

> **Known limitation — same currency only.** A real cross-currency transfer
> (e.g. −100 CHF ↔ +108 EUR) can't be linked yet, because the amounts aren't
> equal and opposite once currencies differ. This constraint lives in
> `TransferMatcher.canLink(_:)` and is a likely candidate to revisit if/when FX
> transfers need support.

## Finding transfers automatically

Tally also detects likely transfers for you: an outgoing charge matched by an
equal, opposite credit on another account within a few days (same currency).
Open the **funnel menu** in the Transactions toolbar and toggle **Suggested
Transfers** — the count next to it is how many candidate pairs were found. The
list narrows to those legs (across all accounts, each pair adjacent) so you can
select a pair and **Link as Transfer**.

Matched pairs share a transfer group id. Opening-balance and rejected entries
are never matched.
