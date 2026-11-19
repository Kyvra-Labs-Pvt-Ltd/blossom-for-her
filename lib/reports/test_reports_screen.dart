import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'test_record.dart';
import 'test_report_pdf.dart';

const _rose = Color(0xFFB84E70);
const _ink = Color(0xFF34262C);

class TestReportsScreen extends StatelessWidget {
  final List<TestRecord> records;
  final String patientName;
  final int patientAge;

  const TestReportsScreen({
    super.key,
    required this.records,
    required this.patientName,
    required this.patientAge,
  });

  @override
  Widget build(BuildContext context) {
    final sorted = [...records]
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
    final captures = sorted.where((r) => !r.isDemo).length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tests & reports'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Your tests'),
              Tab(text: 'Understand results'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _InfoCard(
                  title: 'A clearer record for you and your clinician',
                  body:
                      '${sorted.length} test record${sorted.length == 1 ? '' : 's'} available; $captures reader capture${captures == 1 ? '' : 's'}. '
                      'Calibrated hormone panels: 0. Each report explains what is available, what is missing, and what to discuss. '
                      'Reports are shared only when you choose an export action.',
                ),
                if (sorted.isEmpty)
                  const _InfoCard(
                    title: 'No tests saved yet',
                    body: 'Start a reader test from Hormone test to create a test record.',
                  ),
                for (final record in sorted)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Icon(
                        record.isDemo
                            ? Icons.science_outlined
                            : Icons.description_outlined,
                        color: _rose,
                      ),
                      title: Text(
                        'Test report',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${reportDate(record.capturedAt)}\nCycle day ${record.cycleDay}\n${record.status}',
                          style: const TextStyle(fontSize: 13, height: 1.5),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TestReportDetailScreen(
                            record: record,
                            patientName: patientName,
                            patientAge: patientAge,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const _UnderstandingResults(),
          ],
        ),
      ),
    );
  }
}

class TestReportDetailScreen extends StatefulWidget {
  final TestRecord record;
  final String patientName;
  final int patientAge;
  const TestReportDetailScreen({
    super.key,
    required this.record,
    required this.patientName,
    required this.patientAge,
  });

  @override
  State<TestReportDetailScreen> createState() => _TestReportDetailScreenState();
}

class _TestReportDetailScreenState extends State<TestReportDetailScreen> {
  final notes = TextEditingController();
  bool includeIdentity = true;
  bool includeImage = false;

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  void _openPdf() {
    final record = widget.record;
    final name = includeIdentity ? widget.patientName : null;
    final age = includeIdentity ? widget.patientAge : null;
    final note = notes.text;
    final image = includeImage;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Test PDF report')),
          body: PdfPreview(
            pdfFileName: '${record.displayId}.pdf',
            initialPageFormat: PdfPageFormat.a4,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            build: (_) => buildTestReportPdf(
              record,
              patientName: name,
              patientAge: age,
              notes: note,
              includeImage: image,
            ),
            onError: (_, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'The report could not be prepared. Return to the test and try again.\n$error',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Scaffold(
      appBar: AppBar(title: const Text('Single test report')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Blossom for Her',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 5),
          const Text(
            'KYVRA LABS',
            style: TextStyle(
              color: _rose,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 18),
          _InfoCard(
            title: 'Patient details',
            body:
                'Name: ${widget.patientName}\nAge: ${widget.patientAge} (profile)',
          ),
          _InfoCard(title: record.status, body: record.summary, emphasis: true),
          _InfoCard(
            title: 'Test details',
            body:
                'Report ID: ${record.displayId}\n'
                'Created: ${reportDate(record.capturedAt)}\n'
                'Cycle day: ${record.cycleDay} (based on logged cycle dates)\n'
                'Reader: ${record.isDemo ? 'Not recorded' : record.readerName ?? 'Kyvra reader'}\n'
                'Specimen and strip lot: not recorded',
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hormone values',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final hormone in TestRecord.hormones)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 52,
                            child: Text(
                              hormone,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '${record.resultValue} - ${record.resultAvailability.toLowerCase()}',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Text(
                    'No measured results or validated reference ranges are available yet. Missing values must not be read as low or normal.',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          _InfoCard(title: 'What this means for you', body: record.summary),
          _InfoCard(title: 'For your clinician', body: record.clinicianSummary),
          _InfoCard(title: 'Quality and limitations', body: record.quality),
          const _InfoCard(
            title: 'What to discuss',
            body: 'Bring your cycle history, symptoms, medicines, and laboratory reports. Ask what additional testing or follow-up would help. A single test cannot establish ovulation, pregnancy, PCOS, or ovarian reserve.',
          ),
          if (record.image != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected image - ${record.selectedChannel ?? 'reader channel'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Image.memory(
                      record.image!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('Image preview unavailable.'),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 15),
          Text(
            'Prepare a report to share',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Review the PDF before saving, printing, or sharing it. Identifying details are optional.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Include my name and age',
              style: TextStyle(fontSize: 14),
            ),
            value: includeIdentity,
            onChanged: (v) => setState(() => includeIdentity = v ?? false),
          ),
          if (record.image != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Include the captured image appendix',
                style: TextStyle(fontSize: 14),
              ),
              value: includeImage,
              onChanged: (v) => setState(() => includeImage = v ?? false),
            ),
          TextField(
            controller: notes,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Notes for your clinician (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _openPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Create PDF report'),
          ),
          const SizedBox(height: 18),
          const Text(
            reportDisclaimer,
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _UnderstandingResults extends StatelessWidget {
  const _UnderstandingResults();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: const [
      _InfoCard(
        title: 'Understand the signal, decide with your clinician',
        body: 'A report should explain the observation, its uncertainty, and a useful next question. No pregnancy score or automatic diagnosis is generated.',
        emphasis: true,
      ),
      _InfoCard(
        title: '1. Know where the numbers come from',
        body: 'Reports contain measured results only when analysis is available. A reader capture is an image record. Calibrated hormone concentrations and assay quality checks are not available in this prototype yet.',
      ),
      _InfoCard(
        title: '2. Understand the four markers',
        body: 'E3G: a urinary estrogen metabolite tracked in hormone monitoring.\n\nLH: a rise can help anticipate ovulation, but does not prove it occurred.\n\nPdG: a urinary progesterone metabolite whose pattern may help assess changes after ovulation when measured by a validated assay.\n\nFSH: a hormone involved in follicle development. A single reading is not an ovarian reserve or fertility diagnosis. Urine results are not interchangeable with serum FSH tests.',
      ),
      _InfoCard(
        title: '3. Read changes in context',
        body: 'Interpret repeated, comparable measurements with cycle dates, symptoms, medicines, and laboratory results. This app cannot infer a biological trend from uncalibrated captures.',
      ),
      _InfoCard(
        title: '4. PCOS and irregular cycles',
        body: 'LH patterns can be harder to interpret in PCOS. An LH rise alone must not be labeled as confirmed ovulation. Calendar-based DPO is an estimate; without a supported ovulation date, DPO should remain unknown.',
      ),
      _InfoCard(
        title: 'For you',
        body: 'Save the test record, note relevant symptoms, and use the report to prepare questions. Missing results mean unavailable, not normal.',
      ),
      _InfoCard(
        title: 'For your clinician',
        body: 'Each individual report shows timing, cycle context, data source, quality limitations, and optional user notes. Share only the details you choose. A clinician remains responsible for clinical interpretation.',
      ),
      _InfoCard(
        title: 'Evidence and prototype performance',
        body: 'Published research on other assays does not establish the accuracy of this reader. Analytical agreement, precision, and clinical performance have not been established here. Prototype targets are not reported as achieved accuracy.',
      ),
      _InfoCard(
        title: 'Clinical reading',
        body: 'ASRM patient education: Ovulation Detection\nhttps://www.reproductivefacts.org/news-and-publications/patient-fact-sheets-and-booklets/documents/fact-sheets-and-info-booklets/ovulation-detection/\n\nASRM: Testing and interpreting measures of ovarian reserve (2020)\nhttps://www.asrm.org/practice-guidance/practice-committee-documents/testing-and-interpreting-measures-of-ovarian-reserve-a-committee-opinion-2020/',
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String body;
  final bool emphasis;
  const _InfoCard({
    required this.title,
    required this.body,
    this.emphasis = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: emphasis ? const Color(0xFFFBF0F1) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFEBD8DE)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            color: emphasis ? _rose : _ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        SelectableText(
          body,
          style: const TextStyle(fontSize: 14, height: 1.55, color: _ink),
        ),
      ],
    ),
  );
}
