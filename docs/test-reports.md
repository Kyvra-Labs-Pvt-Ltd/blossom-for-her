# Individual tests and PDF summaries

Open **Tests & reports** from Home, Hormone test, or Hormone Curves. The hub
contains individual records and an **Understand results** guide. A successful
reader capture offers **View test report / create PDF**; **Show demo data** also
creates a clearly labeled example for the selected cycle day.

## Provenance

`TestRecord` currently supports two states only:

- Reader image capture: selected image/channel, reader name, session start time,
  and cycle day derived from the actual test date. All hormone values remain
  unavailable. Image ranking is not a control-line or assay-validity check.
- Demo: simulated relative indices, without concentration units, clinical
  reference ranges, or interpretation. These values cannot enter reader records.

The model stores timestamps in UTC and displays them in the device's local
time. Records are saved in the existing account-local tracking payload,
including the selected image as base64. Original four-channel/dark-frame sets
are not retained. Previous chart entries lack this provenance and are not
silently converted into individual test reports.

If account-local storage is unavailable, the capture remains available for
the current session and the user is prompted to export a copy. The new report
history does not retrofit browser persistence into the native profile store.

## PDF export

Users review one test before creating its PDF. Name and age come from the current
profile and are included by default, with an option to omit them. The image appendix is opt-in. Notes entered on this screen are
included in that export; they are not saved as journal entries. Export opens
the native print/share preview, and no clinician receives data automatically.

The PDF contains the report ID, session date, generation date, cycle day,
source, missing specimen/lot metadata, results availability, quality limits,
and a doctor-verification note. There is no pregnancy probability, fabricated
reference interval, clinician signature, or claimed laboratory accreditation.

Quantitative reports require a future calibrated result model with explicit
units, calibration identity, quality checks, and validated interpretation;
simulated values must not be repurposed as concentrations.

## Checks

```sh
flutter test test/test_record_test.dart test/widget_test.dart
dart run tool/generate_report_examples.dart
```

The example generator uses the same PDF builder as the app. Its delivered
example is `output/pdf/blossom-test-report.pdf`. A capture-layout fixture
is generated under `tmp/pdfs`; it is not a patient result. Passing a synthetic
image path also generates an appendix fixture for layout checks.

Educational text refers to ASRM patient education on ovulation detection and
ASRM's committee opinion on testing/interpreting ovarian reserve (2020).
Published assay results and prototype targets from presentation slides are not
treated as established performance of this device.

PDF presentation: black and white, Times-style fonts, and grayscale image appendices. Reports exclude unmeasured chart indices; result values and units remain unavailable until calibrated analysis exists.

Report presentation now uses neutral Test report labels with the current profile name and age. Unmeasured chart indices are excluded from report result cells; values and units remain unavailable until calibrated analysis exists. Historical source flags remain in local storage and are not converted into measurements.
