# Blossom for Her — Kyvra Labs

## Download Android App

📱 **[Download Blossom for Her APK](https://github.com/Kyvra-Labs-Pvt-Ltd/blossom-for-her/releases/latest)**

Download the latest Android version of Blossom for Her, developed by Kyvra Labs Pvt. Ltd.

Flutter companion app for the Kyvra Labs Blossom for Her hormone reader. It brings cycle tracking, hormone charts, Bluetooth reader capture, and individual test reports into one app.

## Install and run the APK on an Android phone

1. Obtain `app-debug.apk` from the project maintainer, or download `blossom-for-her-debug.apk` from [Releases](https://github.com/Kyvra-Labs-Pvt-Ltd/blossom-for-her/releases/latest). Access to a private repository requires an authorized GitHub account.
2. Transfer the APK to your phone using a USB cable, a file-sharing service, or a direct download.
3. Open the APK in your phone's Files app. If prompted, allow **Install unknown apps** for the app opening the file, then tap **Install**.
4. Open **Blossom for Her**. Choose **Begin your journey** to enter your profile, or **Explore Demo** to explore the interface.
5. For a reader test, turn on Bluetooth, power the reader, and follow the pairing steps below.

**USB debugging is not needed to install an APK manually.** It is needed when deploying from a computer using Flutter or ADB. Android may require approval of an installation from outside the Play Store. The APK cannot be installed on an iPhone.

For updates signed with the same key, install over the existing app to retain local data. Uninstalling the app clears its local data. This project currently uses development signing, including for its release build configuration; production distribution requires a managed signing key.

## Features

| Area | Current behavior |
| --- | --- |
| Profile | Name, age, cycle information, goals, and a local returning-user flow. |
| Daily tracking | Period flow, symptoms, moods, journal entries, calendar, and history views. |
| Hormone charts | LH, E3G, PdG, and FSH overlays, day selection, fertility annotations, and estimated days past ovulation (DPO). |
| Irregular cycles / PCOS | A chart view for irregular patterns; unconfirmed DPO is suppressed until an ovulation date is marked. This view does not diagnose PCOS. |
| Reader pairing | Pair from **Have a reader? → Pair a device**. The app remembers the reader on that phone and provides **Forget device**. |
| Reader capture | Automatic capture across the four internal LED channels and local image selection, with connection/capture progress. No customer LED selection is required. |
| Test reports | Individual saved test records, a guide to understanding results, and PDF export/printing/sharing. Reports use black-and-white, Times-style typography, profile name/age, optional notes, and an optional grayscale image appendix. |
| OVA chat | Built-in offline responses; an optional external chat backend can be configured separately. |
| Partner experience | Partner check-ins and supportive activities. |

### Measurements and interpretation

**Show demo data** retains simulated hormone curves for exploring the chart. These curves are not measurements from the reader. Fertility labels and estimated DPO are tracking aids, not a clinical confirmation of ovulation.

The reader currently transfers images and selects a channel. It does **not** yet quantify hormone concentrations, validate test/control bands, or apply assay calibration curves. Image selection does not establish clinical test validity. Reports show **Analysis pending** and **Not available** for unmeasured results; simulated chart values are not inserted into clinical result cells. The app does not calculate a pregnancy score.

PDF reports include a doctor-verification note. Clinical interpretation and diagnosis require a qualified clinician and validated laboratory testing. Analytical accuracy, reference ranges, and clinical performance have not been established by this app.

See [test report implementation](docs/test-reports.md) for report behavior and remaining analysis work.

## Pair and use the reader

1. Flash the BLE firmware included in this repository onto the ESP32-S3 reader; see [BLE setup](lfa_reader/BLE_SETUP.md).
2. Power the reader and enable Bluetooth on the phone. Allow **Nearby devices** when Android requests permission.
3. Open the assay scan / hormone test screen and select **Have a reader? → Pair a device**. Select the advertised **Kyvra-LFA** reader.
4. Insert the strip and select **Start test**. The app reconnects to the saved reader and handles capture and channel selection automatically.
5. Use **Forget device** to clear the saved reader before pairing a replacement.

Pairing is remembered by the app on that phone. Reinstalling/clearing app data or using another phone may require pairing again. This is an app-managed BLE connection; pairing in Android's Bluetooth settings alone does not complete the app setup.

Bluetooth must remain enabled. **Wi-Fi and internet are not required for reader capture, image transfer, or channel selection.** Optional online chat requires internet; the app's Google Fonts dependency can also request fonts. Full fresh-install operation without any network has not been certified.

The reader captures Green, White, Red, and Blue images, with a matching dark frame for each exposure. LEDs are internal. JPEG transfer uses sequenced chunks, checksums, and acknowledgements. An Android emulator is suitable for UI testing; use a physical phone for real BLE testing.

## Build from source

### Development environment

The current Android build was verified with:

- Flutter **3.47.7** and Dart **3.13.5**. `pubspec.yaml` requires Dart `^3.13.5`.
- Android SDK **37** for `compileSdk`.
- Android Gradle Plugin **9.2.1**, Gradle **9.4.1**, and Kotlin **2.4.0**, pinned in the Android project.
- An Android Studio Java installation compatible with these tools; Java source/bytecode compatibility is set to **17**.

Install Flutter and Android Studio, add Flutter to your PATH, install Android SDK 37 and current command-line tools, and accept Android SDK licenses. Some dependencies may additionally request SDK 34. Initial dependency downloads require internet.

```sh
git clone https://github.com/supratimm24/blossom-for-her.git
cd blossom-for-her
flutter doctor
flutter doctor --android-licenses
flutter pub get
```

Run on an emulator or a USB-connected phone:

```sh
flutter devices
flutter run -d DEVICE_ID
```

For a physical Android phone, enable Developer options and USB debugging, connect a USB data cable, and approve the computer on the phone. For an emulator, start an Android Virtual Device through Android Studio first. Replace `DEVICE_ID` with a value from `flutter devices`.

Build an APK to transfer manually:

```sh
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`. Build outputs are intentionally excluded from Git; distribute APKs separately, for example as private GitHub Release assets.

Run the app checks:

```sh
dart analyze lib/main.dart lib/reports test tool/generate_report_examples.dart
flutter test test/test_record_test.dart test/widget_test.dart
```

### Optional chat backend

The default experience uses local responses. To connect your own backend:

```sh
flutter run --dart-define=CHAT_API_BASE_URL=https://your-backend.example
```

See [the chat backend contract](docs/blossom-chat-backend.md). A backend service is not deployed by this repository. Keep provider secrets on the server, never inside the Flutter app or Git.

### Reader firmware and Python bench tools

Open `lfa_reader/firmware/lfa_reader/lfa_reader.ino` in Arduino IDE, keeping `board_config.h` beside it. The ESP32-S3 build uses **8 MB flash**, **OPI PSRAM**, **Hardware CDC and JTAG**, and **USB CDC on boot**. The firmware was verified with Espressif Arduino core **2.0.17**. See [BLE setup](lfa_reader/BLE_SETUP.md) for the complete board configuration and diagnostics.

The Python tool is for engineering capture/calibration work over USB, separate from the customer's phone flow:

```sh
cd lfa_reader/python
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python lfa_live.py
```

On Windows, activate with `.venv\Scripts\activate`. A Python installation with Tk support is required for the GUI. Sessions are saved locally and excluded from version control. The Python analysis utilities are engineering tools, not validated hormone concentration reporting.

## Source layout

| Path | Purpose |
| --- | --- |
| `lib/main.dart` | Main app, onboarding, tracking, charts, and screens. |
| `lib/lfa_ble_reader.dart` | BLE reader protocol, transfer, and image selection. |
| `lib/reports/` | Test records, report screens, and PDF generation. |
| `lib/chat/` | Local responses and optional backend client. |
| `android/`, `ios/`, `web/`, desktop folders | Flutter platform projects. Android is the currently verified deployment target. |
| `lfa_reader/firmware/lfa_reader/` | ESP32-S3 Arduino firmware and board configuration. |
| `lfa_reader/python/` | USB capture, analysis, calibration GUI, and engineering tests. |
| `assets/` | App images and intro video. |
| `blossom-intro/` | Intro animation source, renderer, and font license. |
| `docs/`, `test/`, `tool/` | Technical notes, Flutter tests, and PDF generation utilities. |

The unusually named file `lib/import 'dart:math' as math;` is a historical source snapshot retained from the working project. The application entry point is `lib/main.dart`.

Local caches, credentials, signing keys, generated reports, capture sessions, firmware build outputs, full-device backups, and duplicate ZIP archives are excluded. The app asset video and the Gradle wrapper needed to build the project are included. This private repository does not grant an open-source license; third-party assets retain their own licenses.

## Troubleshooting

- **SDK 37 is required:** install Android SDK 37. Keep the project's pinned Gradle/AGP versions together rather than independently upgrading one component.
- **Gradle download times out:** check access to `downloads.gradle.org`, then retry the build on a working network. The wrapper has a longer timeout and a pinned distribution checksum.
- **Reader not found:** check power, Bluetooth, Nearby devices permission, correct BLE firmware, and that another phone is not connected. Use `BLESTATUS` in Arduino Serial Monitor at 115200 baud; see the setup guide.
- **No hormone results in a report:** quantification is not implemented yet; a successful capture currently supplies images, not measured concentrations.
- **An update will not install:** check available storage and signing/package compatibility. A build signed with a different development key cannot replace the installed build. Export needed records before any uninstall.
- **iPhone or web use:** platform scaffolding is included, but an APK is Android-only. iOS requires Xcode, signing/provisioning, and device testing. Browser BLE and persistence are not a verified replacement for the Android reader flow.
