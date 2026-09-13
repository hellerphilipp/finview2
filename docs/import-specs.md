# Import specs (adding banks)

An **import spec** is a small declarative YAML file that teaches Tally how to
read one bank's CSV export. It's the same format as the `statement-importer`
Python project: a delimiter, how many header rows to skip, and CEL-subset
expressions that map columns to date, description, amount, and currency.

```yaml
version: "1.0"
name: Revolut
parser:
  delimiter: ","
  skip_rows: 1
mappings:
  timestamp: "row[3] != '' ? row[3] : row[2]"
  description: "row[4]"
  amount_original: "double(row[5])"
  currency_original: "row[7]"
  amount_in_account_currency: "double(row[5])"
```

A spec becomes an **import profile** you can assign to an account (in
**Accounts**), after which it's used whenever you [import a statement](importing.md)
for that account.

## Built-in specs

Tally pre-installs a spec for every bank it ships with (currently **Swisscard**
and **Revolut**) — no setup needed. If you remove a built-in, it stays removed.

## Adding your own

Open **Settings ▸ Import Specs**. Add a spec three ways:

- **Drag** a `.yaml` file onto the drop area.
- **Add from File…** — pick a `.yaml` from disk.
- **Add from URL…** — paste a link to a published spec. The file is downloaded
  **once** and stored in Tally; there's no automatic re-fetch, so re-add the URL
  to pick up a newer version.

Tally validates the spec (including that every mapping expression compiles)
before adding it. If a spec with the same `name` already exists, the new one
**replaces** it rather than creating a duplicate. Remove a spec with the trash
button; if any accounts still use it, you're warned first.

## Sharing specs

Because a spec is just a YAML file, the community can publish specs for banks
Tally doesn't ship — host the file anywhere and share the URL, or send the file
directly. If your bank isn't supported, write a spec (start from the example
above) and add it from disk.
