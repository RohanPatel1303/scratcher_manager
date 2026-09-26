import '../core/barcode_parser.dart';
import '../data/repository.dart';
import '../models/daily_report.dart';
import '../models/models.dart';
import '../models/settings.dart';

/// A friendly error the UI can show directly to the clerk.
class AccountingException implements Exception {
  AccountingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Daily accounting rules.
///
/// Ticket numbers mean "the next ticket to be sold" (the number printed on
/// the top ticket still in the slot). A new book starts at 0, and a sold-out
/// book ends at its size (set per ticket price in Settings). Tickets sold = closing - opening.
class DailyAccountingService {
  DailyAccountingService(this.repo, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final ScratcherRepository repo;
  final DateTime Function() _now;

  // ------------------------------------------------------------ start day

  /// Creates today's sheet, copying opening numbers from the last close.
  /// Returns the existing sheet if today was already started.
  Future<DailyReport> startDay(String date) async {
    final existing = await repo.getReport(date);
    if (existing != null) return existing;

    final latest = await repo.getLatestReport();
    if (latest != null && latest.isOpen) {
      throw AccountingException(
        'Day ${latest.date} is still open. Close it before starting $date.',
      );
    }
    if (latest != null && latest.date.compareTo(date) > 0) {
      throw AccountingException('A later day (${latest.date}) already exists.');
    }

    final settings = await repo.getSettings();
    final books = await repo.getActiveBooks();
    books.sort(_bySlot);

    final lines = <ReportLine>[];
    for (final book in books) {
      final game = await _requireGame(book.gameNumber);
      lines.add(
        _lineFor(book, game, settings, opening: book.lastCountedTicket),
      );
    }

    final report = DailyReport(
      date: date,
      status: ReportStatus.open,
      lines: lines,
      createdAt: _now(),
    );
    await repo.saveReport(report);
    return report;
  }

  // -------------------------------------------------------- enter closing

  /// [input] can be a ticket number ("42") or a full code
  /// ("1234-567890-042-7"). A full code must belong to this book.
  Future<DailyReport> enterClosing({
    required String date,
    required String bookId,
    required String input,
  }) async {
    final report = await _requireOpenReport(date);
    final line = _requireLine(report, bookId);
    final closing = _parseTicketInput(input, bookId);

    if (closing < line.opening) {
      throw AccountingException(
        '${_cap(line.slotLabel)}: closing $closing is '
        'lower than opening ${line.opening}.',
      );
    }
    if (closing > line.ticketsPerBook) {
      throw AccountingException(
        '${_cap(line.slotLabel)}: closing $closing is '
        'more than the ${line.ticketsPerBook} tickets in this book.',
      );
    }

    final updated = report.replaceLine(
      line.copyWith(closing: closing, soldOut: closing == line.ticketsPerBook),
    );
    await repo.saveReport(updated);
    return updated;
  }

  // ------------------------------------------------------------- sold out

  Future<DailyReport> markSoldOut({
    required String date,
    required String bookId,
  }) async {
    final report = await _requireOpenReport(date);
    final line = _requireLine(report, bookId);
    final updated = report.replaceLine(
      line.copyWith(closing: line.ticketsPerBook, soldOut: true),
    );
    await repo.saveReport(updated);
    return updated;
  }

  // ------------------------------------------------------------- new book

  /// Puts a book into a slot and adds it to today's sheet.
  Future<DailyReport> activateBook({
    required String date,
    required int lotNumber,
    required int slotNumber,
    required String gameNumber,
    required String bookNumber,
    int startTicket = 0,
  }) async {
    final report = await _requireOpenReport(date);
    final game = await _requireGame(gameNumber);
    final settings = await repo.getSettings();
    final bookId = '$gameNumber-$bookNumber';
    final size = settings.ticketsForPrice(game.price);

    if (lotNumber < 1 || lotNumber > settings.lotCount) {
      throw AccountingException(
        'Lot $lotNumber does not exist. Pick a lot '
        'from 1 to ${settings.lotCount}, or add lots in Settings.',
      );
    }
    final slots = settings.slotsInLot(lotNumber);
    if (slotNumber < 1 || slotNumber > slots) {
      throw AccountingException(
        'Lot $lotNumber has $slots slot(s). Pick a '
        'slot from 1 to $slots, or add slots in Settings.',
      );
    }
    if (startTicket < 0 || startTicket >= size) {
      throw AccountingException(
        'Start ticket $startTicket is not valid for '
        'a \$${game.price} book of $size tickets.',
      );
    }
    if (report.lines.any(
      (l) =>
          l.lotNumber == lotNumber && l.slotNumber == slotNumber && !l.soldOut,
    )) {
      throw AccountingException(
        'Lot $lotNumber, slot $slotNumber still has a '
        'book that is not sold out.',
      );
    }
    if (report.lineFor(bookId) != null) {
      throw AccountingException('Book $bookId is already on today\'s sheet.');
    }

    final existing = await repo.getBook(bookId);
    if (existing != null && existing.status != BookStatus.inventory) {
      throw AccountingException(
        'Book $bookId is already ${existing.status.name}.',
      );
    }

    final now = _now();
    final book = existing == null
        ? Book(
            gameNumber: gameNumber,
            bookNumber: bookNumber,
            status: BookStatus.active,
            receivedAt: now,
            lotNumber: lotNumber,
            slotNumber: slotNumber,
            lastCountedTicket: startTicket,
            activatedAt: now,
          )
        : existing.copyWith(
            status: BookStatus.active,
            lotNumber: lotNumber,
            slotNumber: slotNumber,
            lastCountedTicket: startTicket,
            activatedAt: now,
          );
    await repo.saveBook(book);

    final lines = [
      ...report.lines,
      _lineFor(book, game, settings, opening: startTicket, addedMidDay: true),
    ]..sort(_lineBySlot);
    final updated = report.copyWith(lines: lines);
    await repo.saveReport(updated);
    return updated;
  }

  /// Same as [activateBook], but from a typed or scanned full code.
  Future<DailyReport> activateBookFromCode({
    required String date,
    required int lotNumber,
    required int slotNumber,
    required String code,
  }) {
    final scan = BarcodeParser.parse(code);
    if (scan is! TicketScan) {
      throw AccountingException('"$code" is not a valid ticket code.');
    }
    return activateBook(
      date: date,
      lotNumber: lotNumber,
      slotNumber: slotNumber,
      gameNumber: scan.gameNumber,
      bookNumber: scan.bookNumber,
      startTicket: scan.ticketNumber,
    );
  }

  // ------------------------------------------------------------ close day

  /// Locks the sheet and saves closings as tomorrow's openings.
  Future<DailyReport> closeDay(String date) async {
    final report = await _requireOpenReport(date);

    final missing = report.missingClosings;
    if (missing.isNotEmpty) {
      throw AccountingException(
        'Missing closing numbers for: '
        '${missing.map((l) => l.slotLabel).join('; ')}.',
      );
    }

    final now = _now();
    for (final line in report.lines) {
      final book = await repo.getBook(line.bookId);
      if (book == null) continue;
      await repo.saveBook(
        line.soldOut
            ? book.copyWith(
                status: BookStatus.soldOut,
                clearSlot: true,
                lastCountedTicket: line.closing,
                closedAt: now,
              )
            : book.copyWith(lastCountedTicket: line.closing),
      );
    }

    final closed = report.copyWith(status: ReportStatus.closed, closedAt: now);
    await repo.saveReport(closed);
    return closed;
  }

  // ------------------------------------------------------------- settings

  Future<StoreSettings> getSettings() => repo.getSettings();

  /// Saves lots, slots and book sizes. Refuses changes that would strand a
  /// book that is in a slot now or has already been sold past the new size.
  Future<void> updateSettings(StoreSettings next) async {
    if (next.lotCount < 1) {
      throw AccountingException('The store needs at least 1 lot.');
    }
    for (var i = 0; i < next.lotCount; i++) {
      if (next.slotsPerLot[i] < 1) {
        throw AccountingException('Lot ${i + 1} needs at least 1 slot.');
      }
    }
    for (final price in kTicketPrices) {
      if (next.ticketsForPrice(price) < 1) {
        throw AccountingException(
          'Enter tickets per book for \$$price tickets (1 or more).',
        );
      }
    }

    for (final book in await repo.getActiveBooks()) {
      final lot = book.lotNumber ?? 1;
      final slot = book.slotNumber ?? 0;
      if (slot > next.slotsInLot(lot)) {
        throw AccountingException(
          'Lot $lot, slot $slot has a book in it. '
          'Move or sell out that book before removing the slot.',
        );
      }
      final game = await _requireGame(book.gameNumber);
      final size = next.ticketsForPrice(game.price);
      if (book.lastCountedTicket > size) {
        throw AccountingException(
          'A \$${game.price} book in lot $lot, slot '
          '$slot is already at ticket ${book.lastCountedTicket}, so books '
          'of \$${game.price} tickets cannot be smaller than that.',
        );
      }
    }
    await repo.saveSettings(next);
  }

  // -------------------------------------------------------------- helpers

  int _parseTicketInput(String input, String bookId) {
    final trimmed = input.trim();
    final asNumber = int.tryParse(trimmed);
    if (asNumber != null && trimmed.length <= 3) return asNumber;

    final scan = BarcodeParser.parse(trimmed);
    if (scan is TicketScan) {
      if (scan.bookId != bookId) {
        throw AccountingException(
          'That code is for book ${scan.bookId}, not $bookId.',
        );
      }
      return scan.ticketNumber;
    }
    throw AccountingException(
      'Enter a ticket number (e.g. 42) or the full ticket code.',
    );
  }

  Future<DailyReport> _requireOpenReport(String date) async {
    final report = await repo.getReport(date);
    if (report == null) {
      throw AccountingException('Day $date has not been started.');
    }
    if (!report.isOpen) {
      throw AccountingException('Day $date is already closed.');
    }
    return report;
  }

  ReportLine _requireLine(DailyReport report, String bookId) {
    final line = report.lineFor(bookId);
    if (line == null) {
      throw AccountingException(
        'Book $bookId is not on the ${report.date} sheet.',
      );
    }
    return line;
  }

  Future<Game> _requireGame(String gameNumber) async {
    final game = await repo.getGame(gameNumber);
    if (game == null) {
      throw AccountingException(
        'Game $gameNumber is not set up yet. Add its name and price '
        'first.',
      );
    }
    return game;
  }

  static int _bySlot(Book a, Book b) {
    final lot = (a.lotNumber ?? 0).compareTo(b.lotNumber ?? 0);
    return lot != 0 ? lot : (a.slotNumber ?? 0).compareTo(b.slotNumber ?? 0);
  }

  static int _lineBySlot(ReportLine a, ReportLine b) {
    final lot = a.lotNumber.compareTo(b.lotNumber);
    return lot != 0 ? lot : a.slotNumber.compareTo(b.slotNumber);
  }

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  ReportLine _lineFor(
    Book book,
    Game game,
    StoreSettings settings, {
    required int opening,
    bool addedMidDay = false,
  }) => ReportLine(
    lotNumber: book.lotNumber ?? 1,
    slotNumber: book.slotNumber ?? 0,
    bookId: book.id,
    gameNumber: book.gameNumber,
    bookNumber: book.bookNumber,
    gameName: game.name,
    price: game.price,
    ticketsPerBook: settings.ticketsForPrice(game.price),
    opening: opening,
    addedMidDay: addedMidDay,
  );
}
