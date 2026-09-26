import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'screens/daily_count_screen.dart';
import 'services/daily_accounting_service.dart';

void main() {
  // Temporary: data lives in memory until Step 4 adds SQLite + Firebase.
  final repo = InMemoryRepository();
  final service = DailyAccountingService(repo);
  runApp(ScratcherApp(service: service));
}

class ScratcherApp extends StatelessWidget {
  const ScratcherApp({super.key, required this.service});

  final DailyAccountingService service;

  static const _seed = Color(0xFF0F6E56); // cash-drawer green

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scratcher Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: _seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: DailyCountScreen(service: service),
    );
  }
}
