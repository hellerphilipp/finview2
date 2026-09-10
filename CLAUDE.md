# CLAUDE.md

Project guidance for Claude Code working in this repository.

## Overview

Two parts share this repo:

1. **`statement-importer`** (repo root, Python) — a library + Flask UI that
   imports CSV bank statements and normalizes them into SQLite via declarative
   YAML/CEL mapping specs. See `README.md`, `src/statement_importer/`.
2. **Tally** (`apple/`) — a native macOS (SwiftUI + SwiftData) app that imports
   statements, reviews/categorizes transactions, matches transfers, reconciles
   work expenses, and reports spending. It reuses the same YAML/CEL import specs,
   evaluated natively by a small CEL-subset interpreter in Swift.

User-facing feature docs live in **`docs/`** (a lightweight wiki).

## Tally (apple/) — structure

- `ImportKit/` — SwiftPM package, pure logic: YAML spec loading + CEL-subset
  evaluator + CSV → `NormalizedRow`. No UI. Test with `swift test`.
- `Tally/Models/` — SwiftData `@Model`s (Account, Transaction, SpendingCategory,
  Merchant, Tag, ImportProfile, ImportBatch), the container, and first-launch seed.
- `Tally/Services/` — pure logic: `ImportService`, `AutoTagger`, `Analytics`,
  `TransferMatcher`, `ExpenseReconciler`.
- `Tally/Views/` — SwiftUI screens; `ContentView` is the sidebar + routing
  (`NavTarget` in `Support/AppRouter.swift`).
- `TallyTests/` — non-hosted unit tests that compile `Tally/Models` + `Tally/Services`
  directly (app-hosted SwiftData tests are crash-prone).

## Build / test / run (Tally)

```sh
cd apple
xcodegen generate            # after adding/removing files (static file list)
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=macOS' -derivedDataPath build build
xcodebuild -project Tally.xcodeproj -scheme Tally -destination 'platform=macOS' -derivedDataPath build test
open build/Build/Products/Debug/Tally.app
```

- Pipe `xcodebuild` through `xcbeautify`. Swift Testing results don't show in the
  XCTest summary — read them with `xcrun xcresulttool get test-results summary --path <xcresult>`.
- UI screenshots: `TALLY_UITEST=1 TALLY_VIEW=<transactions|reports|…> <binary>` seeds
  an in-memory demo store and opens a screen (see `Support/DemoData.swift`).

## Conventions / gotchas

- Regenerate the Xcode project after adding or deleting source files.
- A model named `Category` collides with the ObjC runtime — use `SpendingCategory`.
- Models expose `id: UUID`, so `Table` selection is `Set<UUID>`.
- Keep pure logic in `Services`/`ImportKit` and unit-test it; judge UI by running it.

## Keeping docs updated

**When you add or change a user-facing feature, update `docs/` in the same
change.** The wiki is intended to stay accurate enough to power a future website.
Add a new `docs/<feature>.md` page and link it from `docs/README.md`.
