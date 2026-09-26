/// Core data models for scratcher management.
/// Dates are stored as ISO-8601 strings so the same maps work
/// for local SQLite and for Firestore.

const List<int> kTicketPrices = [1, 2, 5, 10, 20, 30, 50];

// ---------------------------------------------------------------- Game

class Game {
  const Game({
    required this.gameNumber,
    required this.name,
    required this.price,
    this.gameCode,
  });

  final String gameNumber; // e.g. "1234"
  final String name; // e.g. "Lucky 7s"
  final int price; // dollars, one of kTicketPrices
  final String? gameCode; // the second barcode, same on every ticket

  Game copyWith({String? name, int? price, String? gameCode}) => Game(
    gameNumber: gameNumber,
    name: name ?? this.name,
    price: price ?? this.price,
    gameCode: gameCode ?? this.gameCode,
  );

  Map<String, dynamic> toMap() => {
    'gameNumber': gameNumber,
    'name': name,
    'price': price,
    'gameCode': gameCode,
  };

  factory Game.fromMap(Map<String, dynamic> m) => Game(
    gameNumber: m['gameNumber'] as String,
    name: m['name'] as String,
    price: m['price'] as int,
    gameCode: m['gameCode'] as String?,
  );
}

// ---------------------------------------------------------------- Book

enum BookStatus { inventory, active, soldOut, returned }

class Book {
  const Book({
    required this.gameNumber,
    required this.bookNumber,
    required this.status,
    required this.receivedAt,
    this.lotNumber,
    this.slotNumber,
    this.lastCountedTicket = 0,
    this.activatedAt,
    this.closedAt,
  });

  final String gameNumber;
  final String bookNumber;
  final BookStatus status;
  final int? lotNumber; // set while the book is active
  final int? slotNumber; // 1..n inside the lot, set while the book is active

  /// The next ticket to be sold at the last count.
  /// A fresh book starts at 0.
  final int lastCountedTicket;

  final DateTime receivedAt;
  final DateTime? activatedAt;
  final DateTime? closedAt;

  String get id => '$gameNumber-$bookNumber';

  int ticketsRemaining(int ticketsPerBook) =>
      ticketsPerBook - lastCountedTicket;

  Book copyWith({
    BookStatus? status,
    int? lotNumber,
    int? slotNumber,
    bool clearSlot = false,
    int? lastCountedTicket,
    DateTime? activatedAt,
    DateTime? closedAt,
  }) => Book(
    gameNumber: gameNumber,
    bookNumber: bookNumber,
    status: status ?? this.status,
    lotNumber: clearSlot ? null : (lotNumber ?? this.lotNumber),
    slotNumber: clearSlot ? null : (slotNumber ?? this.slotNumber),
    lastCountedTicket: lastCountedTicket ?? this.lastCountedTicket,
    receivedAt: receivedAt,
    activatedAt: activatedAt ?? this.activatedAt,
    closedAt: closedAt ?? this.closedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'gameNumber': gameNumber,
    'bookNumber': bookNumber,
    'status': status.name,
    'lotNumber': lotNumber,
    'slotNumber': slotNumber,
    'lastCountedTicket': lastCountedTicket,
    'receivedAt': receivedAt.toIso8601String(),
    'activatedAt': activatedAt?.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
  };

  factory Book.fromMap(Map<String, dynamic> m) => Book(
    gameNumber: m['gameNumber'] as String,
    bookNumber: m['bookNumber'] as String,
    status: BookStatus.values.byName(m['status'] as String),
    lotNumber: m['lotNumber'] as int? ?? (m['slotNumber'] == null ? null : 1),
    slotNumber: m['slotNumber'] as int?,
    lastCountedTicket: m['lastCountedTicket'] as int? ?? 0,
    receivedAt: DateTime.parse(m['receivedAt'] as String),
    activatedAt: _parseDate(m['activatedAt']),
    closedAt: _parseDate(m['closedAt']),
  );
}

// ---------------------------------------------------------------- Slot

class Slot {
  const Slot({required this.number, this.label});

  final int number; // 1..n
  final String? label; // optional, e.g. "Top row left"

  Map<String, dynamic> toMap() => {'number': number, 'label': label};

  factory Slot.fromMap(Map<String, dynamic> m) =>
      Slot(number: m['number'] as int, label: m['label'] as String?);
}

// ----------------------------------------------------------- ScanEvent

enum ScanAction { receive, activate, count, soldOut, returned }

/// A permanent log of every scan, used for history and reports.
class ScanEvent {
  const ScanEvent({
    required this.id,
    required this.timestamp,
    required this.action,
    required this.bookId,
    required this.raw,
    this.ticketNumber,
    this.slotNumber,
    this.ticketsSold,
  });

  final String id;
  final DateTime timestamp;
  final ScanAction action;
  final String bookId;
  final String raw; // exactly what the scanner sent
  final int? ticketNumber;
  final int? slotNumber;
  final int? ticketsSold; // filled in for count / soldOut events

  Map<String, dynamic> toMap() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'action': action.name,
    'bookId': bookId,
    'raw': raw,
    'ticketNumber': ticketNumber,
    'slotNumber': slotNumber,
    'ticketsSold': ticketsSold,
  };

  factory ScanEvent.fromMap(Map<String, dynamic> m) => ScanEvent(
    id: m['id'] as String,
    timestamp: DateTime.parse(m['timestamp'] as String),
    action: ScanAction.values.byName(m['action'] as String),
    bookId: m['bookId'] as String,
    raw: m['raw'] as String,
    ticketNumber: m['ticketNumber'] as int?,
    slotNumber: m['slotNumber'] as int?,
    ticketsSold: m['ticketsSold'] as int?,
  );
}

// --------------------------------------------------------- Sales math

/// Tickets sold between two counts of the same book.
/// [current] is the next ticket to be sold right now.
int ticketsSoldBetween({required int previous, required int current}) {
  if (current < previous) {
    throw ArgumentError(
      'Current ticket ($current) is lower than last count ($previous).',
    );
  }
  return current - previous;
}

DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.parse(v as String);
