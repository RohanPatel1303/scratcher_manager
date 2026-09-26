/// Store layout and book sizes. Editable in Settings.
/// Stored as one map so it works for SQLite and Firestore.

/// Tickets in one book, by ticket price. Used until changed in Settings.
const Map<int, int> kDefaultTicketsPerBook = {
  1: 200,
  2: 100,
  5: 40,
  10: 40,
  20: 20,
  30: 20,
  50: 20,
};

/// Slots in each lot. Lot 1 has 4 slots, lot 2 has 3.
const List<int> kDefaultSlotsPerLot = [4, 3];

class StoreSettings {
  const StoreSettings({
    this.slotsPerLot = kDefaultSlotsPerLot,
    this.ticketsPerBook = kDefaultTicketsPerBook,
  });

  /// Index 0 is lot 1. Slot numbers restart at 1 in every lot.
  final List<int> slotsPerLot;

  /// Ticket price in dollars -> tickets in one book.
  final Map<int, int> ticketsPerBook;

  int get lotCount => slotsPerLot.length;

  /// Number of slots in [lot] (1-based), or 0 if there is no such lot.
  int slotsInLot(int lot) =>
      lot >= 1 && lot <= lotCount ? slotsPerLot[lot - 1] : 0;

  int ticketsForPrice(int price) =>
      ticketsPerBook[price] ?? kDefaultTicketsPerBook[price] ?? 0;

  StoreSettings copyWith({
    List<int>? slotsPerLot,
    Map<int, int>? ticketsPerBook,
  }) => StoreSettings(
    slotsPerLot: slotsPerLot ?? this.slotsPerLot,
    ticketsPerBook: ticketsPerBook ?? this.ticketsPerBook,
  );

  Map<String, dynamic> toMap() => {
    'slotsPerLot': slotsPerLot,
    'ticketsPerBook': {
      for (final e in ticketsPerBook.entries) '${e.key}': e.value,
    },
  };

  factory StoreSettings.fromMap(Map<String, dynamic> m) => StoreSettings(
    slotsPerLot: [for (final n in (m['slotsPerLot'] as List)) n as int],
    ticketsPerBook: {
      for (final e in (m['ticketsPerBook'] as Map).entries)
        int.parse('${e.key}'): e.value as int,
    },
  );
}
