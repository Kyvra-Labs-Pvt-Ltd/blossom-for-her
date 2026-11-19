import 'dart:typed_data';

import 'package:image/image.dart' as image;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'test_record.dart';

Future<Uint8List> buildTestReportPdf(
  TestRecord record, {
  String? patientName,
  int? patientAge,
  String notes = '',
  bool includeImage = false,
}) async {
  final doc = pw.Document(
    title: 'Blossom for Her - ${record.displayId}',
    author: 'Kyvra Labs',
  );
  const ink = PdfColors.black;
  const rose = PdfColors.black;
  const blush = PdfColors.white;
  Uint8List? grayscaleImage;
  if (includeImage && record.image != null) {
    final decoded = image.decodeImage(record.image!);
    if (decoded != null) {
      grayscaleImage = image.encodePng(image.grayscale(decoded));
    }
  }
  pw.Widget section(String title, String body) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(body, style: const pw.TextStyle(fontSize: 10, lineSpacing: 3)),
      ],
    ),
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: pw.ThemeData.withFont(
        base: pw.Font.times(),
        bold: pw.Font.timesBold(),
      ),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 15),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'KYVRA LABS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    color: rose,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Blossom for Her',
                  style: pw.TextStyle(
                    fontSize: 23,
                    color: ink,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.Text(
              'SINGLE TEST REPORT',
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 9, color: rose, lineSpacing: 4),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: PdfColors.black),
          pw.Text(
            reportDisclaimer,
            style: const pw.TextStyle(fontSize: 8, lineSpacing: 2),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: blush,
            border: pw.Border.all(color: rose),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                record.status.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 12,
                  color: rose,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                record.summary,
                style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerCount: 0,
          border: null,
          cellPadding: const pw.EdgeInsets.symmetric(
            vertical: 4,
            horizontal: 6,
          ),
          cellStyle: const pw.TextStyle(fontSize: 10),
          columnWidths: {0: const pw.FixedColumnWidth(115)},
          data: [
            ['Report ID', record.displayId],
            ['Test captured / created', reportDate(record.capturedAt)],
            ['PDF generated', reportDate(DateTime.now())],
            [
              'Name',
              patientName?.trim().isNotEmpty == true
                  ? patientName!.trim()
                  : 'Not recorded',
            ],
            ['Age (profile)', patientAge?.toString() ?? 'Not recorded'],
            ['Cycle day', '${record.cycleDay} (based on logged cycle dates)'],
            [
              'Device',
              record.isDemo
                  ? 'Not recorded'
                  : '${record.readerName ?? 'Kyvra reader'} / Blossom for Her',
            ],
            ['Specimen / strip lot', 'Not recorded'],
            ['Selected channel', record.selectedChannel ?? 'Not applicable'],
          ],
        ),
        section(
          'Hormone results',
          'Hormone analysis and calibration are pending. No measured results are available. Missing values must not be interpreted as low or normal.',
        ),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: ['Hormone', 'Value', 'Units', 'Availability'],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
          headerStyle: pw.TextStyle(
            color: PdfColors.black,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.all(7),
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          data: [
            for (final h in TestRecord.hormones)
              [
                h,
                record.resultValue,
                'Not available',
                record.resultAvailability,
              ],
          ],
        ),
        section('What this test can tell you', record.clinicianSummary),
        section('Image and assay quality', record.quality),
        section(
          'Discuss with your clinician',
          'Review this record alongside your cycle history, symptoms, medicines, and any laboratory reports. '
              'One test does not establish ovulation, pregnancy, PCOS, or ovarian reserve. '
              'No pregnancy probability or fertility score is calculated.',
        ),
        if (notes.trim().isNotEmpty)
          section('User notes for clinician', notes.trim()),
        if (grayscaleImage != null) ...[
          pw.NewPage(),
          section(
            'Captured image appendix',
            'Selected image shown in grayscale for printing; the original color capture is retained in the app. This image has not been verified as a valid assay result.',
          ),
          pw.SizedBox(height: 12),
          pw.Image(
            pw.MemoryImage(grayscaleImage),
            width: 450,
            height: 420,
            fit: pw.BoxFit.contain,
          ),
        ],
      ],
    ),
  );
  return doc.save();
}
