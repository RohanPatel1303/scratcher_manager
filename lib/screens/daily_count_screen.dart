import 'package:flutter/material.dart';

import '../models/daily_report.dart';
import '../models/models.dart';
import '../services/daily_accounting_service.dart';

import 'package:scratcher_manager/new_book_dialog.dart';

import 'settings_screen.dart';

class DailyCountScreen extends StatefulWidget {
  const DailyCountScreen({super.key, required this.service});

  final DailyAccountingService service;

  @override
  State<DailyCountScreen> createState() => _DailyCountScreenState();
}

class _DailyCountScreenState extends State<DailyCountScreen> {
  DateTime _day = DateTime.now();
  DailyReport? _report;
  bool _loading = true;

  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, String?> _errors = {};

  DailyAccountingService get _svc => widget.service;
  String get _date => dayKey(_day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- data

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _svc.repo.getReport(_date);
    if (!mounted) return;
    setState(() {
      _setReport(r);
      _loading = false;
    });
  }

  /// Keeps one text field + focus node per book on the sheet.
  void _setReport(DailyReport? r) {
    _report = r;
    if (r == null) return;
    for (final line in r.lines) {
      final id = line.bookId;
      final controller = _controllers.putIfAbsent(
        id,
        () => TextEditingController(),
      );
      final node = _focusNodes.putIfAbsent(id, () {
        final n = FocusNode();
        n.addListener(() {
          if (!n.hasFocus) _commit(id); // save when the clerk leaves the box
        });
        return n;
      });
      final text = line.closing?.toString() ?? '';
      if (!node.hasFocus && controller.text != text) controller.text = text;
    }
  }

  Future<void> _commit(String bookId) async {
    final report = _report;
    if (!mounted || report == null || !report.isOpen) return;
    final line = report.lineFor(bookId);
    if (line == null || line.soldOut) return;

    final text = _controllers[bookId]!.text.trim();
    if (text.isEmpty || text == line.closing?.toString()) {
      setState(() => _errors[bookId] = null);
      return;
    }
    try {
      final r = await _svc.enterClosing(
        date: _date,
        bookId: bookId,
        input: text,
      );
      if (!mounted) return;
      setState(() {
        _errors[bookId] = null;
        _setReport(r);
      });
    } on AccountingException catch (e) {
      if (!mounted) return;
      setState(() => _errors[bookId] = e.message);
    }
  }

  Future<void> _run(Future<DailyReport> Function() action) async {
    try {
      final r = await action();
      if (!mounted) return;
      setState(() => _setReport(r));
    } on AccountingException catch (e) {
      _showMessage(e.message);
    }
  }

  // ---------------------------------------------------------- actions

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _day = picked;
      _errors.clear();
    });
    await _load();
  }

  Future<void> _startDay() => _run(() => _svc.startDay(_date));

  Future<void> _soldOut(ReportLine line) async {
    final ok = await _confirm(
      'Mark ${line.slotLabel} sold out?',
      '${line.gameName}, book ${line.bookNumber} will close at ticket '
          '${line.ticketsPerBook}. That is ${line.ticketsPerBook - line.opening} '
          'tickets sold today.',
      'Mark sold out',
    );
    if (!ok) return;
    await _run(() => _svc.markSoldOut(date: _date, bookId: line.bookId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_cap(line.slotLabel)} marked sold out.'),
        action: SnackBarAction(
          label: 'Add new book',
          onPressed: () => _newBook(lot: line.lotNumber, slot: line.slotNumber),
        ),
      ),
    );
  }

  Future<void> _newBook({int? lot, int? slot}) async {
    final report = _report;
    if (report == null) return;

    final suggested = lot != null && slot != null
        ? (lot: lot, slot: slot)
        : await _suggestSlot(report);
    if (!mounted) return;
    final req = await showDialog<NewBookRequest>(
      context: context,
      builder: (_) => NewBookDialog(
        suggestedLot: suggested.lot,
        suggestedSlot: suggested.slot,
      ),
    );
    if (req == null || !mounted) return;

    var game = await _svc.repo.getGame(req.gameNumber);
    if (game == null) {
      if (!mounted) return;
      game = await showDialog<Game>(
        context: context,
        builder: (_) => AddGameDialog(gameNumber: req.gameNumber),
      );
      if (game == null) return;
      await _svc.repo.saveGame(game);
    }

    await _run(
      () => _svc.activateBook(
        date: _date,
        lotNumber: req.lot,
        slotNumber: req.slot,
        gameNumber: req.gameNumber,
        bookNumber: req.bookNumber,
        startTicket: req.startTicket,
      ),
    );
  }

  Future<void> _closeDay() async {
    FocusScope.of(context).unfocus();
    for (final line in _report!.lines) {
      await _commit(line.bookId);
    }
    if (!mounted) return;

    final report = _report!;
    if (_errors.values.any((e) => e != null)) {
      _showMessage('Fix the slots marked in red first.');
      return;
    }
    final missing = report.missingClosings;
    if (missing.isNotEmpty) {
      _showMessage(
        'Enter closing numbers for: '
        '${missing.map((l) => l.slotLabel).join('; ')}.',
      );
      return;
    }

    final ok = await _confirm(
      'Close $_date?',
      '${report.totalTickets} tickets sold, \$${report.totalAmount} total.\n\n'
          'Today\'s closing numbers become tomorrow\'s opening numbers. '
          'A closed day can\'t be edited.',
      'Close day',
    );
    if (ok) await _run(() => _svc.closeDay(_date));
  }

  // ---------------------------------------------------------- helpers

  static String _cap(String s) => s[0].toUpperCase() + s.substring(1);

  /// First empty slot, walking lot 1, lot 2, ... Falls back to lot 1, slot 1.
  Future<({int lot, int slot})> _suggestSlot(DailyReport report) async {
    final settings = await _svc.getSettings();
    final occupied = {
      for (final l in report.lines)
        if (!l.soldOut) (l.lotNumber, l.slotNumber),
    };
    for (var lot = 1; lot <= settings.lotCount; lot++) {
      for (var slot = 1; slot <= settings.slotsInLot(lot); slot++) {
        if (!occupied.contains((lot, slot))) return (lot: lot, slot: slot);
      }
    }
    return (lot: 1, slot: 1);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SettingsScreen(service: _svc)),
    );
  }

  void _focusNext(DailyReport report, int index) {
    for (var i = index + 1; i < report.lines.length; i++) {
      final line = report.lines[i];
      if (!line.soldOut) {
        _focusNodes[line.bookId]?.requestFocus();
        return;
      }
    }
    FocusScope.of(context).unfocus();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // -------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily count'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
          ),
          TextButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(_date),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : report == null
          ? _buildNotStarted()
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusScope.of(context).unfocus(),
              child: _buildSheet(report),
            ),
      floatingActionButton: report != null && report.isOpen
          ? FloatingActionButton.extended(
              onPressed: _newBook,
              icon: const Icon(Icons.add),
              label: const Text('New book'),
            )
          : null,
      bottomNavigationBar: report == null ? null : _buildTotals(report),
    );
  }

  Widget _buildNotStarted() {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_date has not been started', style: t.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Opening numbers are copied from the last closed day.',
              style: t.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startDay,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start day'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheet(DailyReport report) {
    if (report.lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            report.isOpen
                ? 'No books in slots yet. Tap New book to put one in.'
                : 'No books were in slots this day.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: report.lines.length,
      itemBuilder: (_, i) {
        final line = report.lines[i];
        final startsLot =
            i == 0 || report.lines[i - 1].lotNumber != line.lotNumber;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (startsLot) _buildLotHeader(report, line.lotNumber),
            _buildLine(report, line, i),
          ],
        );
      },
    );
  }

  Widget _buildLotHeader(DailyReport report, int lot) {
    final theme = Theme.of(context);
    final lines = report.lines.where((l) => l.lotNumber == lot);
    final amount = lines.fold(0, (sum, l) => sum + l.amount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Lot $lot',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text('\$$amount', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildLine(DailyReport report, ReportLine line, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final error = _errors[line.bookId];
    final editable = report.isOpen && !line.soldOut;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Slot number: the thing the clerk looks for first.
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: line.soldOut
                        ? scheme.surfaceContainerHighest
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${line.slotNumber}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '\$${line.price}  ${line.gameName}',
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Game ${line.gameNumber}, book ${line.bookNumber}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          _stat('Opening', '${line.opening}'),
                          _stat('Sold', '${line.ticketsSold}'),
                          _stat('Amount', '\$${line.amount}'),
                        ],
                      ),
                      if (line.soldOut)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Sold out',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: _controllers[line.bookId],
                    focusNode: _focusNodes[line.bookId],
                    enabled: editable,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                    decoration: InputDecoration(
                      labelText: 'Closing',
                      border: const OutlineInputBorder(),
                      errorText: error == null ? null : '',
                      errorStyle: const TextStyle(height: 0, fontSize: 0),
                    ),
                    onSubmitted: (_) => _focusNext(report, index),
                  ),
                ),
                if (report.isOpen)
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'soldout') _soldOut(line);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'soldout',
                        enabled: !line.soldOut,
                        child: const Text('Mark sold out'),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: Text(
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.labelSmall),
        Text(value, style: t.titleSmall),
      ],
    );
  }

  Widget _buildTotals(DailyReport r) {
    final theme = Theme.of(context);
    final byPrice = r.amountByPrice.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final missing = r.missingClosings.length;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${r.totalTickets} tickets sold',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '\$${r.totalAmount}',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (r.isOpen)
                    FilledButton(
                      onPressed: _closeDay,
                      child: const Text('Close day'),
                    )
                  else
                    const Chip(
                      avatar: Icon(Icons.lock, size: 16),
                      label: Text('Closed'),
                    ),
                ],
              ),
              if (byPrice.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 14,
                    runSpacing: 2,
                    children: [
                      for (final e in byPrice)
                        Text(
                          '\$${e.key} tickets: \$${e.value}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              if (r.isOpen && missing > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$missing slot${missing == 1 ? '' : 's'} still need a '
                    'closing number',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
