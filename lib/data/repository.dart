import '../models/daily_report.dart';
import '../models/models.dart';
import '../models/settings.dart';

/// Everything the app needs to read and write.
/// Step 4 replaces InMemoryRepository with SQLite + Firebase sync,
/// without changing any code that uses this interface.
abstract class ScratcherRepository {
  Future<Game?> getGame(String gameNumber);
  Future<List<Game>> getAllGames();
  Future<void> saveGame(Game game);

  Future<Book?> getBook(String bookId);
  Future<List<Book>> getActiveBooks();
  Future<void> saveBook(Book book);

  /// Returns the defaults until settings are saved.
  Future<StoreSettings> getSettings();
  Future<void> saveSettings(StoreSettings settings);

  Future<DailyReport?> getReport(String date);
  Future<DailyReport?> getLatestReport();
  Future<void> saveReport(DailyReport report);
}

/// Temporary storage that lives only while the app is running.
class InMemoryRepository implements ScratcherRepository {
  final Map<String, Game> _games = {};
  final Map<String, Book> _books = {};
  final Map<String, DailyReport> _reports = {};
  StoreSettings _settings = const StoreSettings();

  @override
  Future<StoreSettings> getSettings() async => _settings;

  @override
  Future<void> saveSettings(StoreSettings settings) async =>
      _settings = settings;

  @override
  Future<Game?> getGame(String gameNumber) async => _games[gameNumber];

  @override
  Future<List<Game>> getAllGames() async => _games.values.toList();

  @override
  Future<void> saveGame(Game game) async => _games[game.gameNumber] = game;

  @override
  Future<Book?> getBook(String bookId) async => _books[bookId];

  @override
  Future<List<Book>> getActiveBooks() async =>
      _books.values.where((b) => b.status == BookStatus.active).toList();

  @override
  Future<void> saveBook(Book book) async => _books[book.id] = book;

  @override
  Future<DailyReport?> getReport(String date) async => _reports[date];

  @override
  Future<DailyReport?> getLatestReport() async {
    if (_reports.isEmpty) return null;
    final keys = _reports.keys.toList()..sort();
    return _reports[keys.last];
  }

  @override
  Future<void> saveReport(DailyReport report) async =>
      _reports[report.date] = report;
}
