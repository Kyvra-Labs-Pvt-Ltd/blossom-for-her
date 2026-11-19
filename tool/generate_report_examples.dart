import 'dart:io';

import 'package:kyvra_app/reports/test_record.dart';
import 'package:kyvra_app/reports/test_report_pdf.dart';

Future<void> main(List<String> arguments) async {
  final demo = TestRecord(
    id: 'KVL-REPORT-001',
    capturedAt: DateTime(2026, 11, 19, 9, 30),
    cycleDay: 15,
    isDemo: true,
    demoValues: {'E3G': 68.5, 'LH': 81.2, 'PdG': 12.4, 'FSH': 28.1},
  );
  await Directory('output/pdf').create(recursive: true);
  await File('output/pdf/blossom-test-report.pdf').writeAsBytes(
    await buildTestReportPdf(demo, patientName: 'Aria', patientAge: 28),
  );
  final capture = TestRecord(
    id: 'EXAMPLE-CAPTURE-001',
    capturedAt: demo.capturedAt,
    cycleDay: 15,
    isDemo: false,
    readerName: 'Kyvra-LFA',
    selectedChannel: 'Green',
  );
  await Directory('tmp/pdfs').create(recursive: true);
  await File('tmp/pdfs/capture-test-report.pdf').writeAsBytes(
    await buildTestReportPdf(
      capture,
      patientName: 'Aria',
      patientAge: 32,
      notes: 'No measured hormone results are available.',
    ),
  );
  if (arguments.isNotEmpty) {
    final fixture = TestRecord(
      id: 'DEMO-IMAGE-FIXTURE',
      capturedAt: demo.capturedAt,
      cycleDay: 15,
      isDemo: true,
      image: await File(arguments.first).readAsBytes(),
      demoValues: demo.demoValues,
    );
    await File('tmp/pdfs/image-appendix-test-report.pdf').writeAsBytes(
      await buildTestReportPdf(
        fixture,
        includeImage: true,
        notes: 'Synthetic image fixture for layout verification only. No real specimen was tested.',
      ),
    );
  }
  stdout.writeln(
    'Generated demo and capture report examples using the app PDF builder.',
  );
}
