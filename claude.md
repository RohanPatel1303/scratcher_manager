# Scratcher Manager

Flutter app (iPhone first) for managing lottery scratcher tickets in a retail
store. The main job is **daily accounting**: record the ticket number showing
in each display slot at the end of each day and calculate sales.

## Commands

- `flutter test`: run all tests (must pass before finishing any task)
- `flutter run`: run the app
- `flutter analyze`: lint

## Domain rules (important)

### Books, games, slots
- Scratchers come in **books** (packs). Each book belongs to a **game**.
- A game has: 4-digit game number, name, price. **Tickets per book is set by
  price** in Settings (`StoreSettings`), not per game.
- Prices are $1, $2, $5, $10, $20, $30, $50 (`kTicketPrices`).
- Default tickets per book: $1=200, $2=100, $5=40, $10=40, $20=20, $30=20,
  $50=20 (`kDefaultTicketsPerBook`). Editable in Settings.
- The store has **lots** (physical display places); each lot has slots numbered
  **1..n, restarting in every lot**. Default: lot 1 has 4 slots, lot 2 has 3.
  Each slot holds one active book. Lots, slots per lot and book sizes are
  editable in Settings (`StoreSettings`); changes that would strand an active
  book are rejected.
- A book's id is `"<gameNumber>-<bookNumber>"`, e.g. `1234-000111`.

### Inventory barcode on each ticket
Format `GGGG-BBBBBB-TTT-C`:
- `GGGG` game number (4 digits)
- `BBBBBB` book number (6 digits)
- `TTT` ticket number (3 digits), **starts at 000 and counts up**
- `C` trailing digit, probably a check digit (ignored)

Scanners may send it without dashes (14 digits); both forms are accepted.
A second barcode is identical on every ticket of the same game (a per-game
code). Its exact format is **not yet confirmed**.

### Ticket number convention (confirmed with the owner)
The clerk writes down **the ticket number showing on the top ticket in the
slot**, i.e. the next ticket to be sold.
- New book opens at 0.
- Sold-out book closes at `ticketsPerBook`.
- **Tickets sold = closing - opening. Amount = tickets sold x price.**

### Daily accounting flow
1. **Start day**: create the day's sheet. Opening numbers are **copied
   automatically** from the previous day's closing numbers (stored on each
   book as `lastCountedTicket`). Clerks never type openings.
2. During the day: a book can be marked **sold out**, and a **new book** can go
   into a slot (a slot can have two lines on one day).
3. End of day: clerk enters one closing number per slot (a plain number like
   `42`, or a full code, which must match that slot's book).
4. **Close day**: blocked if any closing is missing. Saves closings as the next
   openings, retires sold-out books, and locks the sheet.

Validation: closing < opening, closing > book size, full code for a different
book, occupied slot, starting a new day while the previous one is open, and
unknown game (prompts to set up the game) are all rejected.

## Architecture

```
lib/
  core/barcode_parser.dart        parses scanner/typed input (TicketScan, GameCodeScan, UnknownScan)
  models/settings.dart            StoreSettings (lots, slots per lot, tickets per price)
  models/models.dart              Game, Book (BookStatus), Slot, ScanEvent, ticketsSoldBetween()
  models/daily_report.dart        DailyReport, ReportLine, dayKey() ("yyyy-MM-dd")
  data/repository.dart            ScratcherRepository interface + InMemoryRepository (temporary)
  services/daily_accounting_service.dart   all business rules; throws AccountingException
  screens/daily_count_screen.dart main screen (openings prefilled, closings entered, totals, close day)
  screens/settings_screen.dart    lots, slots, tickets per book
  new_book_dialog.dart            NewBookDialog, AddGameDialog
  main.dart
test/
  barcode_parser_test.dart
  daily_accounting_test.dart
```

- **Business logic lives only in `DailyAccountingService`.** Screens call the
  service and show `AccountingException.message` directly to the clerk, so
  those messages must be plain, specific English that says how to fix the issue.
- Models use `toMap`/`fromMap` with ISO-8601 date strings so the same maps work
  for SQLite and Firestore.
- UI state is plain `StatefulWidget` + `setState` for now.
- Scanner input: Bluetooth scanners act as a keyboard (type code + Enter), so
  scanning works through normal text fields. Closing fields save on focus loss,
  and Enter moves to the next slot.

## Decisions made

- Flutter, iPhone first (building for iOS needs a Mac with Xcode, or Codemagic).
- Storage: **local SQLite (Drift) is the source of truth**, synced to
  **Firebase (Firestore + Auth)** as the cloud copy. The app must work fully offline.
- Manual entry first; the barcode scanner is not available yet.

## Roadmap

- [x] Step 1: barcode parser + models
- [x] Step 2: daily accounting engine + tests
- [x] Step 3: Daily Count screen
- [ ] **Step 4 (next)**: replace `InMemoryRepository` with a Drift/SQLite
  repository (same interface), then add Firebase sync (push local changes when
  online, sync queue, Firebase Auth sign-in)
- [ ] Step 5: reports: history of closed days, sales by slot/game/price, CSV export
- [ ] Step 6: inventory: receive books before activation, return unsold books,
  on-hand list
- [x] Step 7 (partly): settings for lots, slots and tickets per book
- [ ] Step 7: game list editing
- [ ] Later: reopen/correct a closed day (with audit trail), multiple users or
  devices, and verifying real scanner output once the scanner arrives

## Open questions

- Actual raw output of the scanner for both barcodes (the data encoded may differ
  from the printed digits; adjust `BarcodeParser` once tested).
- Format and use of the per-game barcode.
- How returns of unsold tickets to the lottery should be accounted for.

## Working style

- Build step by step; keep each change small and tested.
- Add or update tests in `test/` for any change to rules in the service.
- Keep UI copy plain and in sentence case.