# Transactions & review

**Transactions** is the unified browser for everything you've imported. Pick
**All Transactions** or a specific account in the sidebar; filter by status with
the **All / To Review / Confirmed** control. Columns (Date, Account,
Description, Amount, Category, Work, Status) are click-to-sort.

Review happens right here — select one or more rows and act via the toolbar,
the **Transaction** menu, or keyboard shortcuts:

- **⌘K** — assign a category (searchable palette)
- **⌘J** — accept the suggested category
- **⌘W** — toggle "work expense"
- **⌘↩** — confirm · **⌘⌫** — reject

Pending rows needing review are counted as **badges** on the sidebar (toggle in
Settings). Confirming a row with an accepted suggestion applies that category,
so a reviewed row shows a verified category rather than a suggestion.

## Status bar

Enable **Show status bar** in Settings for a Finder-style bar along the bottom
of the ledger. It summarizes, right-aligned, what you're looking at:

- The transaction count — **N transactions** when everything is visible, or
  **Showing X of Y transactions** when a status filter or search is narrowing
  the list.
- When you select **two or more** rows, the selected count and their **sum** —
  e.g. **2 transactions selected. Sum: CHF 0.00**. The sum only appears when the
  selected rows share one currency; with mixed currencies it shows just the count.

## Search

Press **⌘F** (or click the search field in the top-right of the toolbar, which
expands on demand) to search the ledger. Search narrows the list live and works
alongside the status filter and account scope.

It matches broadly across each transaction's **description**, original bank
text, **merchant**, **category**, **account**, **tags**, **note**, **amount**,
and **currency**. Type multiple words to require all of them — so `netflix 12`
finds Netflix rows near CHF 12, and `CHF 64` finds a 64.00 charge on a CHF
account. Clearing the field restores the full list.
