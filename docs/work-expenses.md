# Work expenses

Work purchases are often paid on a personal or work card, then posted as line
items to a separate expense account which later reimburses them. Tally helps you
not forget any.

Workflow:

1. Tag work purchases with **⌘W** (a briefcase shows on those rows).
2. Mark your reimbursement account as the **work expense account**
   ([accounts.md](accounts.md)). Post each expense there as a positive line item
   mirroring the card charge.
3. Tally **reconciles**: each work-tagged −X charge is matched to a +X line item
   in the expense account (equal magnitude, within a date window).

- **Unmatched** work charges — ones you likely forgot to expense — are listed in
  a **Dashboard** section ("N unclaimed · total") and flagged with a ⚠️ next to
  the briefcase in the transaction list.
- A matched line item **inherits the category** of its originating card charge.

Reconciliation is informational — nothing is required. The eventual payout is
just a normal transfer out of the expense account (see [transfers.md](transfers.md)).
