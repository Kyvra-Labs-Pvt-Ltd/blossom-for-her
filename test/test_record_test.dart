import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kyvra_app/reports/test_record.dart';

void main() {
  test('capture timestamps are stored as UTC instants', () {
    final local = DateTime(2026, 11, 19, 9, 30);
    final record = TestRecord(
      id: 'timezone-test',
      capturedAt: local,
      cycleDay: 1,
      isDemo: false,
    );
    final json = record.toJson();
    expect(json['capturedAt'], endsWith('Z'));
    final restored = TestRecord.fromJson(json);
    expect(restored.capturedAt.isAtSameMomentAs(local), isTrue);
  });

  test('demo numbers cannot become results in a real capture', () {
    final record = TestRecord(
      id: 'capture',
      capturedAt: DateTime(2026),
      cycleDay: 1,
      isDemo: false,
      demoValues: {'LH': 92},
    );
    expect(record.demoValues, isEmpty);
    expect(record.summary, contains('not available'));
    expect(record.quality, contains('have not been evaluated'));
  });

  test(
    'a saved test retains time, image, source, and relative demo values',
    () {
      final record = TestRecord(
        id: 'demo',
        capturedAt: DateTime.utc(2026, 11, 19, 4),
        cycleDay: 14,
        isDemo: true,
        image: Uint8List.fromList([1, 2, 3]),
        demoValues: {'LH': 40.5},
      );
      final restored = TestRecord.fromJson(record.toJson());
      expect(restored.capturedAt, record.capturedAt);
      expect(restored.isDemo, isTrue);
      expect(restored.demoValues, {'LH': 40.5});
      expect(restored.image, [1, 2, 3]);
      expect(restored.toJson(), record.toJson());
    },
  );

  test('malformed dates and invalid cycle days are rejected', () {
    final json = TestRecord(
      id: 'test',
      capturedAt: DateTime(2026),
      cycleDay: 1,
      isDemo: true,
    ).toJson();
    expect(
      () => TestRecord.fromJson({...json, 'capturedAt': 'invalid'}),
      throwsFormatException,
    );
    expect(
      () => TestRecord.fromJson({...json, 'cycleDay': 0}),
      throwsFormatException,
    );
  });

  test('non-finite and unknown demo markers are excluded on load', () {
    final json = TestRecord(
      id: 'test',
      capturedAt: DateTime(2026),
      cycleDay: 1,
      isDemo: true,
    ).toJson();
    final restored = TestRecord.fromJson({
      ...json,
      'demoValues': {'LH': double.nan, 'FSH': 20, 'unknown': 8},
    });
    expect(restored.demoValues, {'FSH': 20.0});
  });
}
