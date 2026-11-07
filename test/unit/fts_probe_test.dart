// Probe: does the SQLite this project links have FTS5 + trigram?
// Runs under `flutter test` so Flutter/dart:ui symbols resolve.
// Prints the result via the test reporter; does not fail on FTS unavailability
// because the design intentionally falls back to LIKE.
import 'package:ai_assistant/data/local/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FTS5 availability probe', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    // Force the open / beforeOpen path so _ensureFts() runs.
    await db.customSelect('SELECT 1').getSingle();

    // This line is the actual answer we want in the test output.
    // ignore: avoid_print
    print('isFtsAvailable: ${db.isFtsAvailable}');
    if (!db.isFtsAvailable) {
      // ignore: avoid_print
      print('ftsUnavailableReason: ${db.ftsUnavailableReason}');
    }

    await db.close();
    // No assertion: FTS unavailability is acceptable (LIKE fallback).
    expect(true, isTrue);
  });
}
