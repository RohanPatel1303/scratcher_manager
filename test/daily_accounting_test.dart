import 'package:flutter_test/flutter_test.dart';
import 'package:scratcher_manager/data/repository.dart';
import 'package:scratcher_manager/models/daily_report.dart';
import 'package:scratcher_manager/models/models.dart';
import 'package:scratcher_manager/models/settings.dart';
import 'package:scratcher_manager/services/daily_accounting_service.dart';

void main() {
  late InMemoryRepository repo;
  late DailyAccountingService svc;
  const day1 = '2026-09-18';
  const day2 = '2026-09-19';
  const day3 = '2026-09-20';

  setUp(() async {
    repo = InMemoryRepository();
    svc = DailyAccountingService(repo, clock: () => DateTime(2026, 9, 18, 9));
    await repo.saveGame(
      const Game(gameNumber: '1234', name: 'Lucky 7s', price: 5),
    );
    await repo.saveGame(
      const Game(gameNumber: '5678', name: 'Cash Pop', price: 1),
    );
  });

  /// Day 1: two new books, $5 sells 25, $1 sells 100.
  Future<void> runDay1() async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 2,
      gameNumber: '5678',
      bookNumber: '000222',
    );
    await svc.enterClosing(date: day1, bookId: '1234-000111', input: '25');
    await svc.enterClosing(date: day1, bookId: '5678-000222', input: '100');
    await svc.closeDay(day1);
  }

  test('first day totals', () async {
    await runDay1();
    final r = (await repo.getReport(day1))!;
    expect(r.status, ReportStatus.closed);
    expect(r.totalTickets, 125);
    expect(r.totalAmount, 225); // 25 x $5 + 100 x $1
    expect(r.amountByPrice, {5: 125, 1: 100});
  });

  test('opening numbers are copied from previous day', () async {
    await runDay1();
    final r = await svc.startDay(day2);
    expect(r.lineFor('1234-000111')!.opening, 25);
    expect(r.lineFor('5678-000222')!.opening, 100);
  });

  test('sold out and new book in the same slot', () async {
    await runDay1();
    await svc.startDay(day2);
    await svc.markSoldOut(
      date: day2,
      bookId: '1234-000111',
    ); // 15 sold (book of 40, opening 25)
    await svc.activateBookFromCode(
      date: day2,
      lotNumber: 1,
      slotNumber: 1,
      code: '1234-000112-000-5',
    );
    await svc.enterClosing(date: day2, bookId: '1234-000112', input: '10');
    await svc.enterClosing(date: day2, bookId: '5678-000222', input: '150');
    final r = await svc.closeDay(day2);
    expect(r.totalAmount, 175); // 15x5 + 10x5 + 50x1

    final next = await svc.startDay(day3);
    expect(next.lines.length, 2);
    expect(next.lineFor('1234-000111'), isNull);
    expect(next.lineFor('1234-000112')!.opening, 10);
  });

  test('full code for the right book is accepted', () async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    final r = await svc.enterClosing(
      date: day1,
      bookId: '1234-000111',
      input: '1234-000111-030-2',
    );
    expect(r.lineFor('1234-000111')!.closing, 30);
  });

  test('full code for a different book is rejected', () async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    await expectLater(
      svc.enterClosing(
        date: day1,
        bookId: '1234-000111',
        input: '5678-000222-010-1',
      ),
      throwsA(isA<AccountingException>()),
    );
  });

  test('closing lower than opening is rejected', () async {
    await runDay1();
    await svc.startDay(day2);
    await expectLater(
      svc.enterClosing(date: day2, bookId: '1234-000111', input: '10'),
      throwsA(isA<AccountingException>()),
    );
  });

  test('cannot put a book into an occupied slot', () async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    await expectLater(
      svc.activateBook(
        date: day1,
        lotNumber: 1,
        slotNumber: 1,
        gameNumber: '5678',
        bookNumber: '000222',
      ),
      throwsA(isA<AccountingException>()),
    );
  });

  test('cannot close a day with missing closing numbers', () async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    await expectLater(svc.closeDay(day1), throwsA(isA<AccountingException>()));
  });

  test('cannot start a new day while the previous one is open', () async {
    await svc.startDay(day1);
    await expectLater(svc.startDay(day2), throwsA(isA<AccountingException>()));
  });

  test('unknown game asks to be set up first', () async {
    await svc.startDay(day1);
    await expectLater(
      svc.activateBook(
        date: day1,
        lotNumber: 1,
        slotNumber: 1,
        gameNumber: '9999',
        bookNumber: '000001',
      ),
      throwsA(isA<AccountingException>()),
    );
  });

  test('book size follows the ticket price', () async {
    await svc.startDay(day1);
    final r = await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '5678',
      bookNumber: '000222',
    );
    expect(r.lines.single.ticketsPerBook, 200); // $1 book
    await expectLater(
      svc.enterClosing(date: day1, bookId: '5678-000222', input: '201'),
      throwsA(isA<AccountingException>()),
    );
  });

  test('default book sizes', () {
    const s = StoreSettings();
    expect(
      [for (final p in kTicketPrices) s.ticketsForPrice(p)],
      [200, 100, 40, 40, 20, 20, 20],
    );
  });

  test('slot numbers restart in each lot', () async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    // Same slot number in lot 2 is a different slot.
    final r = await svc.activateBook(
      date: day1,
      lotNumber: 2,
      slotNumber: 1,
      gameNumber: '5678',
      bookNumber: '000222',
    );
    expect(r.lines.map((l) => (l.lotNumber, l.slotNumber)), [(1, 1), (2, 1)]);
  });

  test('lot and slot must exist', () async {
    await svc.startDay(day1);
    // Default layout: lot 1 has 4 slots, lot 2 has 3, no lot 3.
    for (final (lot, slot) in [(1, 5), (2, 4), (3, 1), (1, 0)]) {
      await expectLater(
        svc.activateBook(
          date: day1,
          lotNumber: lot,
          slotNumber: slot,
          gameNumber: '1234',
          bookNumber: '000111',
        ),
        throwsA(isA<AccountingException>()),
        reason: 'lot $lot slot $slot',
      );
    }
  });

  test('settings can add lots and slots', () async {
    await svc.updateSettings(const StoreSettings(slotsPerLot: [4, 3, 6]));
    await svc.startDay(day1);
    final r = await svc.activateBook(
      date: day1,
      lotNumber: 3,
      slotNumber: 6,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    expect(r.lines.single.lotNumber, 3);
  });

  test('settings can change tickets per book', () async {
    await svc.updateSettings(
      StoreSettings(ticketsPerBook: {...kDefaultTicketsPerBook, 5: 50}),
    );
    await svc.startDay(day1);
    final r = await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 1,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    expect(r.lines.single.ticketsPerBook, 50);
  });

  test('settings cannot remove a slot that holds a book', () async {
    await svc.startDay(day1);
    await svc.activateBook(
      date: day1,
      lotNumber: 1,
      slotNumber: 4,
      gameNumber: '1234',
      bookNumber: '000111',
    );
    await expectLater(
      svc.updateSettings(const StoreSettings(slotsPerLot: [3, 3])),
      throwsA(isA<AccountingException>()),
    );
    await expectLater(
      svc.updateSettings(const StoreSettings(slotsPerLot: [4])),
      completes,
    ); // lot 2 was empty
  });

  test('settings cannot shrink a book below tickets already sold', () async {
    await runDay1(); // $5 book is at ticket 25
    await expectLater(
      svc.updateSettings(
        StoreSettings(ticketsPerBook: {...kDefaultTicketsPerBook, 5: 20}),
      ),
      throwsA(isA<AccountingException>()),
    );
  });

  test('settings reject zero lots, slots or tickets', () async {
    for (final bad in [
      const StoreSettings(slotsPerLot: []),
      const StoreSettings(slotsPerLot: [4, 0]),
      StoreSettings(ticketsPerBook: {...kDefaultTicketsPerBook, 1: 0}),
    ]) {
      await expectLater(
        svc.updateSettings(bad),
        throwsA(isA<AccountingException>()),
      );
    }
  });

  test('settings survive toMap/fromMap', () {
    final s = StoreSettings.fromMap(
      const StoreSettings(slotsPerLot: [2, 5]).toMap(),
    );
    expect(s.slotsPerLot, [2, 5]);
    expect(s.ticketsForPrice(30), 20);
  });
}
