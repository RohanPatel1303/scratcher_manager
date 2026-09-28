import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  /// Slots for every lot seen on this screen, including lots removed by
  /// lowering the lot count, so typing "12" (which passes through "1") does
  /// not lose lot 2's slots.
  List<int>? _lotSizes;
  int _lotCount = 0;
  Map<int, int>? _tickets;
  String? _error;

  List<int> get _slotsPerLot => _lotSizes!.take(_lotCount).toList();

  @override
  void initState() {
    super.initState();
    widget.service.getSettings().then((s) {
      if (!mounted) return;
      setState(() {
        _lotSizes = [...s.slotsPerLot];
        _lotCount = s.lotCount;
        _tickets = {for (final p in kTicketPrices) p: s.ticketsForPrice(p)};
      });
    });
  }

  void _setLotCount(int n) {
    final sizes = _lotSizes!;
    while (sizes.length < n) {
      sizes.add(sizes.isEmpty ? 4 : sizes.last);
    }
    _lotCount = n;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    try {
      await widget.service.updateSettings(
        StoreSettings(slotsPerLot: _slotsPerLot, ticketsPerBook: _tickets!),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on AccountingException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Widget _numberRow(
    String label,
    int value,
    ValueChanged<int> onChanged, {
    int min = 1,
    int maxDigits = 2,
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
            width: 56,
            child: _NumberField(
              label: label,
              value: value,
              min: min,
              maxDigits: maxDigits,
              onChanged: onChanged,
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
    final sizes = _lotSizes;
    final tickets = _tickets;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: sizes == null ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: sizes == null || tickets == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                _numberRow(
                  'Number of lots',
                  _lotCount,
                  (n) => setState(() => _setLotCount(n)),
                ),
                for (var i = 0; i < _lotCount; i++)
                  _numberRow(
                    'Lot ${i + 1} slots',
                    sizes[i],
                    (n) => setState(() => sizes[i] = n),
                  ),
                _header('Tickets per book'),
                for (final price in kTicketPrices)
                  _numberRow(
                    '\$$price book',
                    tickets[price]!,
                    (n) => setState(() => tickets[price] = n),
                    maxDigits: 3,
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

/// Whole-number field that opens the number pad. Reports each valid value as
/// it is typed; an empty or too-small entry goes back to the last valid value
/// when the field loses focus.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.min,
    required this.maxDigits,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int maxDigits;
  final ValueChanged<int> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      } else {
        _controller.text = '${widget.value}';
      }
    });
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Follow the − / + buttons, but leave the text alone while it already
    // shows the value (for example mid-typing).
    if (widget.value != old.value &&
        int.tryParse(_controller.text) != widget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(widget.maxDigits),
        ],
        style: Theme.of(context).textTheme.titleMedium,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(),
        ),
        onTapOutside: (_) => _focus.unfocus(),
        onChanged: (text) {
          final n = int.tryParse(text);
          if (n != null && n >= widget.min && n != widget.value) {
            widget.onChanged(n);
          }
        },
      ),
    );
  }
}
