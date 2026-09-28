import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scratcher_manager/data/repository.dart';
import 'package:scratcher_manager/screens/settings_screen.dart';
import 'package:scratcher_manager/services/daily_accounting_service.dart';

void main() {
  late InMemoryRepository repo;

  Future<void> openSettings(WidgetTester tester) async {
    repo = InMemoryRepository();
    final svc = DailyAccountingService(repo);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(service: svc),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.descendant(
    of: find.widgetWithText(ListTile, label),
    matching: find.byType(TextField),
  );

  testWidgets('fields use the number keyboard', (tester) async {
    await openSettings(tester);
    final tf = tester.widget<TextField>(field('\$5 book'));
    expect(tf.keyboardType, TextInputType.number);
  });

  testWidgets('typed values are saved', (tester) async {
    await openSettings(tester);
    await tester.enterText(field('Lot 1 slots'), '6');
    await tester.enterText(field('\$5 book'), '60');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final s = await repo.getSettings();
    expect(s.slotsPerLot, [6, 3]);
    expect(s.ticketsForPrice(5), 60);
  });

  testWidgets('typing a multi-digit lot count keeps existing lots',
      (tester) async {
    await openSettings(tester);
    // "12" passes through "1", which must not forget lot 2's 3 slots.
    await tester.enterText(field('Number of lots'), '1');
    await tester.pump();
    await tester.enterText(field('Number of lots'), '12');
    await tester.pump();
    await tester.enterText(field('Number of lots'), '3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await repo.getSettings()).slotsPerLot, [4, 3, 3]);
  });

  testWidgets('letters and zero are not accepted', (tester) async {
    await openSettings(tester);
    await tester.enterText(field('Lot 1 slots'), 'a');
    await tester.enterText(field('Lot 1 slots'), '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect((await repo.getSettings()).slotsPerLot, [4, 3]);
  });

  testWidgets('plus button updates the field', (tester) async {
    await openSettings(tester);
    await tester.tap(find.descendant(
      of: find.widgetWithText(ListTile, 'Lot 2 slots'),
      matching: find.byTooltip('More'),
    ));
    await tester.pump();
    expect(
      tester.widget<TextField>(field('Lot 2 slots')).controller!.text,
      '4',
    );
  });
}
