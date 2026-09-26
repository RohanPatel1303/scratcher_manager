/// Parses raw text coming from the Bluetooth barcode scanner.
///
/// Inventory barcode format: GGGG-BBBBBB-TTT-C
///   GGGG   = game number (4 digits)
///   BBBBBB = book number (6 digits)
///   TTT    = ticket number (3 digits, starts at 000)
///   C      = trailing digit (likely a check digit)
///
/// Scanners often send the code without dashes, so both
/// "1234-567890-042-7" and "12345678900427" are accepted.

sealed class ScanResult {
  const ScanResult({required this.raw});
  final String raw;
}

/// A scan of the inventory barcode on a ticket.
class TicketScan extends ScanResult {
  const TicketScan({
    required super.raw,
    required this.gameNumber,
    required this.bookNumber,
    required this.ticketNumber,
    required this.checkDigit,
  });

  final String gameNumber;
  final String bookNumber;
  final int ticketNumber;
  final String checkDigit;

  /// Unique id for the book: game + book number.
  String get bookId => '$gameNumber-$bookNumber';

  @override
  String toString() =>
      'TicketScan(game: $gameNumber, book: $bookNumber, ticket: $ticketNumber)';
}

/// A scan of the per-game barcode (same on every ticket of a game).
class GameCodeScan extends ScanResult {
  const GameCodeScan({required super.raw});
  String get code => raw;

  @override
  String toString() => 'GameCodeScan($code)';
}

/// Anything we could not recognise.
class UnknownScan extends ScanResult {
  const UnknownScan({required super.raw});

  @override
  String toString() => 'UnknownScan($raw)';
}

class BarcodeParser {
  static final RegExp _dashed = RegExp(r'^(\d{4})-(\d{6})-(\d{3})-(\d)$');
  static final RegExp _plain = RegExp(r'^(\d{4})(\d{6})(\d{3})(\d)$');
  static final RegExp _numericCode = RegExp(r'^\d{8,}$');

  static ScanResult parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) return UnknownScan(raw: raw);

    final match = _dashed.firstMatch(raw) ?? _plain.firstMatch(raw);
    if (match != null) {
      return TicketScan(
        raw: raw,
        gameNumber: match.group(1)!,
        bookNumber: match.group(2)!,
        ticketNumber: int.parse(match.group(3)!),
        checkDigit: match.group(4)!,
      );
    }

    if (_numericCode.hasMatch(raw)) {
      return GameCodeScan(raw: raw);
    }

    return UnknownScan(raw: raw);
  }
}
