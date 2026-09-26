import 'package:flutter/material.dart';

import '../core/barcode_parser.dart';
import '../models/models.dart';

class NewBookRequest {
  const NewBookRequest({
    required this.lot,
    required this.slot,
    required this.gameNumber,
    required this.bookNumber,
    required this.startTicket,
  });

  final int lot;
  final int slot;
  final String gameNumber;
  final String bookNumber;
  final int startTicket;
}

// ------------------------------------------------------------ validators

String? Function(String?) _exactDigits(int n) =>
    (v) => RegExp('^\\d{$n}\$').hasMatch(v?.trim() ?? '')
    ? null
    : 'Enter exactly $n digits';

String? _positiveInt(String? v) {
  final n = int.tryParse(v?.trim() ?? '');
  return n != null && n > 0 ? null : 'Enter a number of 1 or more';
}

String? _nonNegativeInt(String? v) {
  final n = int.tryParse(v?.trim() ?? '');
  return n != null && n >= 0 ? null : 'Enter 0 or more';
}

Widget _numberField(
  TextEditingController c,
  String label, {
  String? Function(String?)? validator,
  String? helper,
}) => Padding(
  padding: const EdgeInsets.only(top: 12),
  child: TextFormField(
    controller: c,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      border: const OutlineInputBorder(),
    ),
    validator: validator,
  ),
);

// ------------------------------------------------------------- new book

class NewBookDialog extends StatefulWidget {
  const NewBookDialog({
    super.key,
    required this.suggestedLot,
    required this.suggestedSlot,
  });

  final int suggestedLot;
  final int suggestedSlot;

  @override
  State<NewBookDialog> createState() => _NewBookDialogState();
}

class _NewBookDialogState extends State<NewBookDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _lot = TextEditingController(text: '${widget.suggestedLot}');
  late final _slot = TextEditingController(text: '${widget.suggestedSlot}');
  final _code = TextEditingController();
  final _game = TextEditingController();
  final _book = TextEditingController();
  final _start = TextEditingController(text: '0');

  @override
  void dispose() {
    for (final c in [_lot, _slot, _code, _game, _book, _start]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Typing (or later scanning) a full code fills in the other fields.
  void _onCode(String value) {
    final scan = BarcodeParser.parse(value);
    if (scan is TicketScan) {
      _game.text = scan.gameNumber;
      _book.text = scan.bookNumber;
      _start.text = '${scan.ticketNumber}';
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      NewBookRequest(
        lot: int.parse(_lot.text.trim()),
        slot: int.parse(_slot.text.trim()),
        gameNumber: _game.text.trim(),
        bookNumber: _book.text.trim(),
        startTicket: int.parse(_start.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New book'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _numberField(_lot, 'Lot number', validator: _positiveInt),
              _numberField(
                _slot,
                'Slot number in the lot',
                validator: _positiveInt,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  controller: _code,
                  decoration: const InputDecoration(
                    labelText: 'Full ticket code (optional)',
                    hintText: '1234-567890-000-0',
                    helperText: 'Fills in the fields below',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _onCode,
                ),
              ),
              _numberField(
                _game,
                'Game number',
                validator: _exactDigits(4),
                helper: '4 digits',
              ),
              _numberField(
                _book,
                'Book number',
                validator: _exactDigits(6),
                helper: '6 digits',
              ),
              _numberField(
                _start,
                'Ticket showing in the slot',
                validator: _nonNegativeInt,
                helper: '0 for a new book',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add book')),
      ],
    );
  }
}

// ------------------------------------------------------------- new game

class AddGameDialog extends StatefulWidget {
  const AddGameDialog({super.key, required this.gameNumber});

  final String gameNumber;

  @override
  State<AddGameDialog> createState() => _AddGameDialogState();
}

class _AddGameDialogState extends State<AddGameDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  int? _price;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Game(
        gameNumber: widget.gameNumber,
        name: _name.text.trim(),
        price: _price!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set up game ${widget.gameNumber}'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'This game is new. Enter its name and price once. '
                'Tickets per book come from Settings.',
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Game name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Enter a name' : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Ticket price',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final p in kTicketPrices)
                      DropdownMenuItem(value: p, child: Text('\$$p')),
                  ],
                  onChanged: (v) => setState(() => _price = v),
                  validator: (v) => v == null ? 'Pick a price' : null,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save game')),
      ],
    );
  }
}
