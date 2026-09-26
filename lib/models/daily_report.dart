/// A daily accounting sheet: one line per book that was in a slot that day.
/// A slot can have two lines on the same day if a book sold out and a new
/// book was put in its place.

enum ReportStatus { open, closed }

/// "yyyy-MM-dd" key for a day. Sorts correctly as a string.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class ReportLine {
  const ReportLine({
    required this.lotNumber,
    required this.slotNumber,
    required this.bookId,
    required this.gameNumber,
    required this.bookNumber,
    required this.gameName,
    required this.price,
    required this.ticketsPerBook,
    required this.opening,
    this.closing,
    this.soldOut = false,
    this.addedMidDay = false,
  });

  final int lotNumber;
  final int slotNumber; // 1..n inside the lot
  final String bookId;
  final String gameNumber;
  final String bookNumber;
  final String gameName;
  final int price;
  final int ticketsPerBook;

  /// Next ticket to be sold at the start of the day (copied from yesterday).
  final int opening;

  /// Next ticket to be sold at the end of the day. Null until entered.
  final int? closing;

  final bool soldOut;
  final bool addedMidDay;

  /// Plain label for messages, e.g. "lot 2, slot 3".
  String get slotLabel => 'lot $lotNumber, slot $slotNumber';

  bool get isComplete => closing != null;
  int get ticketsSold => closing == null ? 0 : closing! - opening;
  int get amount => ticketsSold * price;

  ReportLine copyWith({int? closing, bool? soldOut}) => ReportLine(
    lotNumber: lotNumber,
    slotNumber: slotNumber,
    bookId: bookId,
    gameNumber: gameNumber,
    bookNumber: bookNumber,
    gameName: gameName,
    price: price,
    ticketsPerBook: ticketsPerBook,
    opening: opening,
    closing: closing ?? this.closing,
    soldOut: soldOut ?? this.soldOut,
    addedMidDay: addedMidDay,
  );

  Map<String, dynamic> toMap() => {
    'lotNumber': lotNumber,
    'slotNumber': slotNumber,
    'bookId': bookId,
    'gameNumber': gameNumber,
    'bookNumber': bookNumber,
    'gameName': gameName,
    'price': price,
    'ticketsPerBook': ticketsPerBook,
    'opening': opening,
    'closing': closing,
    'soldOut': soldOut,
    'addedMidDay': addedMidDay,
  };

  factory ReportLine.fromMap(Map<String, dynamic> m) => ReportLine(
    lotNumber: m['lotNumber'] as int? ?? 1,
    slotNumber: m['slotNumber'] as int,
    bookId: m['bookId'] as String,
    gameNumber: m['gameNumber'] as String,
    bookNumber: m['bookNumber'] as String,
    gameName: m['gameName'] as String,
    price: m['price'] as int,
    ticketsPerBook: m['ticketsPerBook'] as int,
    opening: m['opening'] as int,
    closing: m['closing'] as int?,
    soldOut: m['soldOut'] as bool? ?? false,
    addedMidDay: m['addedMidDay'] as bool? ?? false,
  );
}

class DailyReport {
  const DailyReport({
    required this.date,
    required this.status,
    required this.lines,
    required this.createdAt,
    this.closedAt,
  });

  final String date; // yyyy-MM-dd
  final ReportStatus status;
  final List<ReportLine> lines;
  final DateTime createdAt;
  final DateTime? closedAt;

  bool get isOpen => status == ReportStatus.open;

  int get totalTickets => lines.fold(0, (sum, l) => sum + l.ticketsSold);
  int get totalAmount => lines.fold(0, (sum, l) => sum + l.amount);

  List<ReportLine> get missingClosings =>
      lines.where((l) => !l.isComplete).toList();

  /// Dollar sales grouped by ticket price, e.g. {1: 100, 5: 125}.
  Map<int, int> get amountByPrice {
    final result = <int, int>{};
    for (final l in lines) {
      result[l.price] = (result[l.price] ?? 0) + l.amount;
    }
    return result;
  }

  ReportLine? lineFor(String bookId) {
    for (final l in lines) {
      if (l.bookId == bookId) return l;
    }
    return null;
  }

  DailyReport copyWith({
    ReportStatus? status,
    List<ReportLine>? lines,
    DateTime? closedAt,
  }) => DailyReport(
    date: date,
    status: status ?? this.status,
    lines: lines ?? this.lines,
    createdAt: createdAt,
    closedAt: closedAt ?? this.closedAt,
  );

  DailyReport replaceLine(ReportLine updated) => copyWith(
    lines: [for (final l in lines) l.bookId == updated.bookId ? updated : l],
  );

  Map<String, dynamic> toMap() => {
    'date': date,
    'status': status.name,
    'lines': lines.map((l) => l.toMap()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'closedAt': closedAt?.toIso8601String(),
  };

  factory DailyReport.fromMap(Map<String, dynamic> m) => DailyReport(
    date: m['date'] as String,
    status: ReportStatus.values.byName(m['status'] as String),
    lines: (m['lines'] as List)
        .map((e) => ReportLine.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    createdAt: DateTime.parse(m['createdAt'] as String),
    closedAt: m['closedAt'] == null
        ? null
        : DateTime.parse(m['closedAt'] as String),
  );
}
