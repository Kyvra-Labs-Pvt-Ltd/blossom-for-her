import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kyvra_app/reports/test_record.dart';
import 'package:kyvra_app/reports/test_reports_screen.dart';

void main() {
  testWidgets('report hub explains missing tests and offers the guide', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: TestReportsScreen(
          records: [],
          patientName: 'Private name',
          patientAge: 32,
        ),
      ),
    );
    expect(find.text('No tests saved yet'), findsOneWidget);
    await tester.tap(find.text('Understand results'));
    await tester.pumpAndSettle();
    expect(
      find.text('Understand the signal, decide with your clinician'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('report uses profile details and excludes unmeasured indices', (
    tester,
  ) async {
    final record = TestRecord(
      id: 'DEMO-TEST',
      capturedAt: DateTime(2026, 11, 19),
      cycleDay: 15,
      isDemo: true,
      demoValues: {'LH': 81.2},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TestReportsScreen(
          records: [record],
          patientName: 'Private name',
          patientAge: 32,
        ),
      ),
    );
    await tester.tap(find.text('Test report'));
    await tester.pumpAndSettle();
    expect(find.text('Analysis pending'), findsOneWidget);
    expect(find.text('81.2 - UI'), findsNothing);
    expect(find.textContaining('Private name'), findsOneWidget);
    final reportScroll = find
        .descendant(
          of: find.byType(TestReportDetailScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Hormone values'),
      350,
      scrollable: reportScroll,
    );
    expect(find.text('Not available - analysis pending'), findsNWidgets(4));
    await tester.scrollUntilVisible(
      find.text('Include my name and age'),
      350,
      scrollable: reportScroll,
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isTrue,
    );
    await tester.scrollUntilVisible(
      find.text('Create PDF report'),
      200,
      scrollable: reportScroll,
    );
    expect(find.text('Create PDF report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real capture shows unavailable results instead of demo concentrations',
    (tester) async {
      final record = TestRecord(
        id: 'CAPTURE',
        capturedAt: DateTime(2026, 11, 19),
        cycleDay: 15,
        isDemo: false,
        demoValues: {'LH': 99},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TestReportDetailScreen(
            record: record,
            patientName: 'Private name',
            patientAge: 32,
          ),
        ),
      );
      expect(find.text('Analysis pending'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Hormone values'),
        350,
        scrollable: find
            .descendant(
              of: find.byType(TestReportDetailScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Not available - analysis pending'), findsNWidgets(4));
      expect(find.textContaining('99 -'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
