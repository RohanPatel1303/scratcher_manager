import 'package:flutter/material.dart';

import '../models/models.dart';
import '../models/settings.dart';
import '../services/daily_accounting_service.dart';

/// Number of lots, slots in each lot, and tickets per book by price.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.service});

  final DailyAccountingService service;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<int>? _slotsPerLot;
  Map<int, int>? _tickets;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.service.getSettings().then((s) {
      if (!mounted) return;
      setState(() {
        _slotsPerLot = [...s.slotsPerLot];
        _tickets = {for (final p in kTicketPrices) p: s.ticketsForPrice(p)};
      });
    });
  }

  Future<void> _save() async {
    try {
      await widget.service.updateSettings(
        StoreSettings(slotsPerLot: _slotsPerLot!, ticketsPerBook: _tickets!),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Widget _stepper(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 1,
  }) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fewer',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slotsPerLot;
    final tickets = _tickets;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: slots == null ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: slots == null || tickets == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                _header('Lots'),
                _stepper('Number of lots', slots.length, (n) {
                  setState(() {
                    if (n > slots.length) {
                      slots.add(slots.isEmpty ? 4 : slots.last);
                    } else {
                      slots.removeLast();
                    }
                  });
                }),
                for (var i = 0; i < slots.length; i++)
                  _stepper(
                    'Lot ${i + 1} slots',
                    slots[i],
                    (n) => setState(() => slots[i] = n),
                  ),
                _header('Tickets per book'),
                for (final price in kTicketPrices)
                  _stepper(
                    '\$$price book',
                    tickets[price]!,
                    (n) => setState(() => tickets[price] = n),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    'Changes to tickets per book apply to books that go into a '
                    'slot after saving, and to days started after saving.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
