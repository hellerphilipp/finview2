# Linking transactions (transfers & refunds)

Some transactions belong together: the two legs of a transfer between your own
accounts, or a purchase and the refund you later get back. Tally lets you **link**
them into one group. Linked transactions:

- **share one category** — set it on any member and the whole group follows;
- **stay together in the list** — the group's rows sit adjacent no matter how you
  sort, with the charge first and its refund(s)/opposite leg beneath it;
- **show a glyph** — ↔ for a transfer, ↩ for a refund, whose tooltip names the
  account on the other side;
- **stay legible under a filter or search** — if a status filter or search matches
  only one member, the others still appear right beside it in **gray**, so a pair
  is never shown half-hidden.

Linking happens inside the **Transactions** view — there's no separate screen.

## How linked groups affect reports

One uniform rule: **a group contributes the *net* of its signed amounts to its
shared category.** Nothing is special-cased.

| Group (shared category) | Net | Counts as |
|---|---|---|
| −2'000 + 2'000 (transfer) | 0 | nothing — money just moved |
| −10 + 10 (full refund) | 0 | nothing |
| −250 + 50 (partial refund) | −200 | 200 spend in that category |

So a transfer naturally nets to zero (it never inflates spending), and a
partially-refunded purchase counts only for what you actually kept.

## Transfers

Money moved between your own accounts — e.g. −2'000 CHF on Current ↔ +2'000 CHF
on Savings. Select the two rows, right-click, and choose **Link as Transfer**.
The command appears only for a valid pair:

- **exactly 2 rows**, on **different accounts**, in the **same currency**, with
  **equal-and-opposite amounts** (one −X, the other +X).

**Finding transfers automatically:** open the **funnel menu** in the toolbar and
toggle **Suggested Transfers** — the count is how many candidate pairs were found
(an outgoing charge matched by an equal, opposite credit on another account
within a few days). The list narrows to those legs, each pair adjacent, so you
can select and **Link as Transfer**.

> **Known limitation — same currency only.** A real cross-currency transfer
> (−100 CHF ↔ +108 EUR) can't be linked as a transfer yet, because the amounts
> aren't equal and opposite once currencies differ (`TransferMatcher.canLink`).

## Refunds

A charge and the money you got back — a returned order, a price adjustment, or a
friend reimbursing you. Select the charge together with its refund(s), right-click,
and choose **Link as Refund**. Valid when the selection is:

- **one charge** (a negative amount) plus **one or more refunds** (positive), in
  the **same currency**. Accounts may differ, and refunds don't have to add up to
  the charge (partial refunds are fine).

Examples:

- **Partial order refund** — a −250 order and a later +50 refund on the same card
  → Shopping nets to 200.
- **Cross-account reimbursement** — a −100 group dinner on your card, and a +50
  the friend Venmos into your current account → Dining nets to 50.

On linking, the group adopts the **charge's category**; recategorizing any member
(⌘K) re-applies it to the whole group.

## Unlinking

Right-click any linked row and choose **Unlink** to remove the link from every
member of the group. Opening-balance and rejected entries are never linked.
