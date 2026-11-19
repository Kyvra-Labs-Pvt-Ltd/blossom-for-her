# Kyvra LFA BLE setup

The Flutter app and firmware use the same BLE service and packet format. Image
transfer and channel selection run locally on the phone; Wi-Fi and internet are
not used for a test.

## Flash the ESP32-S3

1. Use the `lfa_reader/firmware/lfa_reader` folder from the updated archive.
   Open `lfa_reader.ino` in Arduino IDE; keep `board_config.h` beside it.
2. Select **ESP32S3 Dev Module**, **PSRAM: OPI PSRAM**, **Flash: 8 MB**,
   **Partition Scheme: 8M with spiffs (3MB APP/1.5MB SPIFFS)**,
   **USB Mode: Hardware CDC and JTAG**, and **USB CDC On Boot: Enabled**.
   Keep the core debug level at **None**.
3. Connect the board by USB and upload the sketch. The USB serial commands stay
   available for the Python bench tool. The board also advertises as
   `Kyvra-LFA` over BLE.

The sketch uses the BLE library bundled with the Espressif Arduino core; no
separate BLE library needs to be installed.

The BLE capture exposure defaults match the Python tool: Green 300, White 150,
Red 300, Blue 450, with gain 0. If you tuned different exposure values for
your strip and enclosure, update `BLE_EXPOSURES` in the sketch before upload.

The phone sends `START`. The board captures Green, White, Red, and Blue images,
plus one LED-off dark frame at each channel's exposure, then sends all eight
JPEGs in sequenced chunks. Each chunk has a checksum, and the phone acknowledges
each 16-chunk window so the transfer can detect loss or corruption.

## Run the Flutter app

1. From the Flutter project, run `flutter pub get` if dependencies have not
   already been resolved.
2. Install/run the app on a physical Android phone or iPhone. On Android, allow
   Nearby Devices when prompted. On iPhone, allow Bluetooth when prompted.
3. On the hormone test screen, choose **Have a reader? > Pair a device** once.
   The reader is remembered on this phone; **Forget device** clears it.
4. Insert the strip in the reader and tap **Start test**. The app reconnects to
   the saved reader, captures the images, and selects a channel automatically.

If the app cannot find the reader, connect it to a computer with a USB data
cable and inspect startup output at 115200 baud. The BLE sketch prints
`BLE ready: Kyvra-LFA`. The original USB-only sketch does not advertise over
Bluetooth and must be replaced with this sketch.
Send `BLESTATUS` in Serial Monitor for the advertised name, service UUID,
camera readiness, and connection state. When idle and ready for pairing,
`advertising=1 camera=1 busy=0` should be reported.

The current app displays the selected image. It does not calculate hormone
concentrations or add values to the cycle chart yet. Those results require the
assay's fixed test/control band definitions and validated calibration curves.
