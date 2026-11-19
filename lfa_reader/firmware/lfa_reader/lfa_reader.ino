/*
 * lfa_reader.ino  --  ESP32-S3 + OV2640/OV3660 lateral-flow strip imager
 *
 * The ESP32 supports both the existing USB-serial bench protocol and a BLE
 * GATT session for the Flutter app. BLE sends each LED image and its matching
 * dark image as acknowledged JPEG chunks; analysis runs locally in the app.
 *
 * Arduino IDE settings (Tools menu):
 *   Board ............ ESP32S3 Dev Module   (arduino-esp32 core 2.0.14+ or 3.x)
 *   PSRAM ............ OPI PSRAM             <-- required for N8R8
 *   Flash Size ....... 8MB,  Flash Mode: QIO 80 MHz
 *   USB CDC On Boot .. Enabled   (use the USB port wired to GPIO19/20)
 *   Core Debug Level . None      (keeps log text out of the serial stream)
 *
 * Serial protocol (text lines, '\n' terminated, 115200 - ignored on native USB):
 *   PING                       -> "OK LFAREADER 1"
 *   LED <G|W|R|B|OFF>          -> turn one LED on (for focusing/alignment) / all off
 *   SET res <QVGA|VGA|SVGA|XGA|SXGA|UXGA>
 *   SET quality <4..63>        (JPEG quality, LOWER = better)
 *   SET exposure <0..1200>     (default exposure for CAP)
 *   SET gain <0..30>           (default analog gain for CAP)
 *   SET settle <ms>            (LED settle time before grabbing, default 150)
 *   SET discard <n>            (frames thrown away after LED switch, default 3)
 *   CAP <G|W|R|B|NONE> [exposure] [gain]
 *        -> "IMG <nbytes> <w> <h>\n" + <nbytes of JPEG> + "OK\n"
 *        NONE = LED off (dark frame, use it for ambient/black-level subtraction)
 *   MASK <0-15>                -> several LEDs at once (G=1 W=2 R=4 B=8)
 *   FRAME                      -> newest frame, LEDs unchanged (live view)
 *   STATUS                     -> current settings
 *   Errors are reported as "ERR <message>".
 */

#include "esp_camera.h"
#include "board_config.h"
#include <cstring>
#include <string>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE UUIDs shared with lib/lfa_ble_reader.dart.
static const char* BLE_DEVICE_NAME = "Kyvra-LFA";
static const char* BLE_SERVICE_UUID = "8f9c1000-2d70-4e31-a5b2-5fa97c11a001";
static const char* BLE_COMMAND_UUID = "8f9c1001-2d70-4e31-a5b2-5fa97c11a001";
static const char* BLE_IMAGE_UUID   = "8f9c1002-2d70-4e31-a5b2-5fa97c11a001";
static const char* BLE_STATUS_UUID  = "8f9c1003-2d70-4e31-a5b2-5fa97c11a001";
static constexpr size_t BLE_PACKET_HEADER = 21;
static constexpr size_t BLE_CHUNK_BYTES = 160; // fits an iOS MTU of 185
static constexpr uint32_t BLE_ACK_WINDOW = 16;

static BLECharacteristic* g_bleImage = nullptr;
static BLECharacteristic* g_bleStatus = nullptr;
static volatile bool g_bleConnected = false;
static volatile bool g_bleStartRequested = false;
static volatile bool g_bleCancelRequested = false;
static volatile bool g_bleSessionRunning = false;
static volatile bool g_bleAdvertising = false;
static volatile bool g_bleAdvertisingResult = false;
static volatile uint32_t g_bleAckNextSequence = 0;
static bool g_cameraReady = false;

class LfaServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    g_bleConnected = true;
    g_bleAdvertising = false;
    if (g_bleStatus && !g_bleSessionRunning) {
      g_bleStatus->setValue(g_cameraReady ? "READY" : "ERROR: camera is not ready");
    }
  }
  void onDisconnect(BLEServer* server) override {
    g_bleConnected = false;
    g_bleCancelRequested = true;
    g_bleStartRequested = false;
    server->startAdvertising();
  }
};

class LfaCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    // Core 2.x returns std::string; core 3.x returns Arduino String.
    const auto value = characteristic->getValue();
    if (value == "START") {
      if (!g_bleSessionRunning && !g_bleStartRequested) {
        g_bleCancelRequested = false;
        g_bleStartRequested = true;
      }
    } else if (value == "CANCEL") {
      g_bleCancelRequested = true;
    } else if (value.length() >= 5 && (uint8_t)value[0] == 0xAC) {
      g_bleAckNextSequence = (uint8_t)value[1]
          | ((uint32_t)(uint8_t)value[2] << 8)
          | ((uint32_t)(uint8_t)value[3] << 16)
          | ((uint32_t)(uint8_t)value[4] << 24);
    }
  }
};

static void setBleStatus(const String& message) {
  if (!g_bleStatus) return;
  g_bleStatus->setValue(message.c_str());
  if (g_bleConnected) g_bleStatus->notify();
}

static void putU32(uint8_t* out, uint32_t value) {
  out[0] = value & 0xff;
  out[1] = (value >> 8) & 0xff;
  out[2] = (value >> 16) & 0xff;
  out[3] = (value >> 24) & 0xff;
}

static uint32_t crc32(const uint8_t* data, size_t length) {
  uint32_t crc = 0xffffffff;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (int bit = 0; bit < 8; ++bit) {
      crc = (crc & 1) ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return ~crc;
}

static bool waitForBleAck(uint32_t nextSequence) {
  uint32_t started = millis();
  while (g_bleConnected && !g_bleCancelRequested &&
         g_bleAckNextSequence < nextSequence) {
    if (millis() - started > 20000) {
      setBleStatus("ERROR: image transfer timed out waiting for phone");
      return false;
    }
    delay(2);
  }
  return g_bleConnected && !g_bleCancelRequested;
}

static bool sendBleFrame(camera_fb_t* fb, uint8_t frameIndex, uint8_t ledCode,
                         uint32_t& sequence) {
  if (!g_bleImage || !fb || !fb->buf || !fb->len) return false;
  uint32_t offset = 0;
  while (offset < fb->len) {
    if (!g_bleConnected || g_bleCancelRequested) return false;
    size_t count = fb->len - offset;
    if (count > BLE_CHUNK_BYTES) count = BLE_CHUNK_BYTES;

    uint8_t packet[BLE_PACKET_HEADER + BLE_CHUNK_BYTES];
    packet[0] = 0x4b;
    packet[1] = 0x56;
    packet[2] = 1; // image data
    putU32(packet + 3, sequence);
    packet[7] = frameIndex;
    packet[8] = ledCode;
    putU32(packet + 9, (uint32_t)fb->len);
    putU32(packet + 13, offset);
    putU32(packet + 17, crc32(fb->buf + offset, count));
    memcpy(packet + BLE_PACKET_HEADER, fb->buf + offset, count);

    g_bleImage->setValue(packet, BLE_PACKET_HEADER + count);
    g_bleImage->notify();
    sequence++;
    offset += count;
    delay(2);

    if (sequence % BLE_ACK_WINDOW == 0 && !waitForBleAck(sequence)) return false;
  }
  return true;
}

static void sendBleDone(uint32_t sequence) {
  if (!g_bleImage || !g_bleConnected) return;
  uint8_t packet[BLE_PACKET_HEADER] = {};
  packet[0] = 0x4b;
  packet[1] = 0x56;
  packet[2] = 2; // session complete
  putU32(packet + 3, sequence);
  packet[7] = 0xff;
  packet[8] = 0xff;
  g_bleImage->setValue(packet, sizeof(packet));
  g_bleImage->notify();
}

static void handleBleGapEvent(esp_gap_ble_cb_event_t event,
                              esp_ble_gap_cb_param_t* parameter) {
  if (event == ESP_GAP_BLE_ADV_START_COMPLETE_EVT) {
    g_bleAdvertising = parameter->adv_start_cmpl.status == ESP_BT_STATUS_SUCCESS;
    g_bleAdvertisingResult = true;
  } else if (event == ESP_GAP_BLE_ADV_STOP_COMPLETE_EVT) {
    g_bleAdvertising = false;
  }
}

static bool startBleService() {
  BLEDevice::init(BLE_DEVICE_NAME);
  BLEDevice::setCustomGapHandler(handleBleGapEvent);
  BLEDevice::setMTU(185);
  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new LfaServerCallbacks());
  BLEService* service = server->createService(BLE_SERVICE_UUID);

  BLECharacteristic* command = service->createCharacteristic(
      BLE_COMMAND_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  command->setCallbacks(new LfaCommandCallbacks());

  g_bleImage = service->createCharacteristic(
      BLE_IMAGE_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  g_bleImage->addDescriptor(new BLE2902());

  g_bleStatus = service->createCharacteristic(
      BLE_STATUS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  g_bleStatus->addDescriptor(new BLE2902());
  g_bleStatus->setValue(g_cameraReady ? "READY" : "ERROR: camera is not ready");
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(BLE_SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
  const uint32_t started = millis();
  while (!g_bleAdvertisingResult && millis() - started < 2000) delay(10);
  return g_bleAdvertising;
}

// ----------------------------------------------------------------------------
struct LedDef { const char* name; int pin; };
static LedDef LEDS[] = {
  {"G", LED_GREEN},   // bit 0 for MASK
  {"W", LED_WHITE},   // bit 1
  {"R", LED_RED},     // bit 2
  {"B", LED_BLUE},    // bit 3
};
static const int NLED = sizeof(LEDS) / sizeof(LEDS[0]);
static const int BLE_EXPOSURES[NLED] = {300, 150, 300, 450}; // G, W, R, B

// ---- runtime settings ------------------------------------------------------
static framesize_t g_res      = FRAMESIZE_SXGA;   // 1280x1024: ~50+ px across a 1 mm band at ~30 mm
static int         g_quality  = 4;
static int         g_exposure = 300;              // OV2640 aec_value 0..1200
static int         g_gain     = 0;                // agc_gain 0..30
static int         g_settleMs = 150;
static int         g_discard  = 3;

// ----------------------------------------------------------------------------
static inline void ledWrite(int pin, bool on) {
  if (pin < 0) return;
  digitalWrite(pin, (on == (LED_ACTIVE_HIGH != 0)) ? HIGH : LOW);
}

static void allLedsOff() {
  for (int i = 0; i < NLED; i++) ledWrite(LEDS[i].pin, false);
}

// Turn on exactly one LED by name. Returns false if the name is unknown/unwired.
static bool ledOnly(const String& name0) {
  String name = (name0 == "X") ? String("R") : name0;   // "X" = old name of the red LED
  allLedsOff();
  if (name == "OFF" || name == "NONE") return true;
  for (int i = 0; i < NLED; i++) {
    if (name == LEDS[i].name) {
      if (LEDS[i].pin < 0) return false;
      ledWrite(LEDS[i].pin, true);
      return true;
    }
  }
  return false;
}

// ----------------------------------------------------------------------------
// Lock everything that would otherwise change brightness/colour between shots.
static void lockSensor() {
  sensor_t* s = esp_camera_sensor_get();
  if (!s) return;
  s->set_brightness(s, 0);
  s->set_contrast(s, 0);
  s->set_saturation(s, 0);
  s->set_special_effect(s, 0);
  s->set_whitebal(s, 0);        // no auto white balance
  s->set_awb_gain(s, 0);
  s->set_wb_mode(s, 0);
  s->set_exposure_ctrl(s, 0);   // no auto exposure
  s->set_aec2(s, 0);
  s->set_gain_ctrl(s, 0);       // no auto gain
  s->set_gainceiling(s, (gainceiling_t)0);
  s->set_bpc(s, 0);
  s->set_wpc(s, 1);
  s->set_raw_gma(s, 1);
  s->set_lenc(s, 0);            // lens-shading correction OFF (we flat-field in software)
  s->set_dcw(s, 0);
  s->set_colorbar(s, 0);
  s->set_hmirror(s, 0);
  s->set_vflip(s, 0);
  s->set_aec_value(s, g_exposure);
  s->set_agc_gain(s, g_gain);
}

static void applyRes();
static void applyQuality();

static bool initCamera() {
  camera_config_t c = {};
  c.ledc_channel = LEDC_CHANNEL_0;
  c.ledc_timer   = LEDC_TIMER_0;
  c.pin_d0 = CAM_D0; c.pin_d1 = CAM_D1; c.pin_d2 = CAM_D2; c.pin_d3 = CAM_D3;
  c.pin_d4 = CAM_D4; c.pin_d5 = CAM_D5; c.pin_d6 = CAM_D6; c.pin_d7 = CAM_D7;
  c.pin_xclk = CAM_XCLK;
  c.pin_pclk = CAM_PCLK;
  c.pin_vsync = CAM_VSYNC;
  c.pin_href = CAM_HREF;
  c.pin_sccb_sda = CAM_SDA;
  c.pin_sccb_scl = CAM_SCL;
  c.pin_pwdn = CAM_PWDN;
  c.pin_reset = CAM_RESET;
  c.xclk_freq_hz = 20000000;
  c.pixel_format = PIXFORMAT_JPEG;
  c.frame_size   = FRAMESIZE_UXGA;   // allocate buffers for the largest size, then shrink
  c.jpeg_quality = g_quality;
  c.fb_count     = 2;
  c.fb_location  = CAMERA_FB_IN_PSRAM;
  c.grab_mode    = CAMERA_GRAB_LATEST;   // always hand back the newest frame

  esp_err_t err = esp_camera_init(&c);
  if (err != ESP_OK) return false;
  applyRes();
  applyQuality();
  lockSensor();
  return true;
}

static void applyRes() {
  sensor_t* s = esp_camera_sensor_get();
  if (s) s->set_framesize(s, g_res);
}

static void applyQuality() {
  sensor_t* s = esp_camera_sensor_get();
  if (s) s->set_quality(s, g_quality);
}

// ----------------------------------------------------------------------------
static int g_appliedExp = -1, g_appliedGain = -1;
static void applyExpGain(int e, int g) {
  sensor_t* s = esp_camera_sensor_get();
  if (!s) return;
  if (e != g_appliedExp)  { s->set_aec_value(s, e); g_appliedExp = e; }
  if (g != g_appliedGain) { s->set_agc_gain(s, g);  g_appliedGain = g; }
}

static void sendFb(camera_fb_t* fb) {
  Serial.printf("IMG %u %u %u\n", (unsigned)fb->len, (unsigned)fb->width, (unsigned)fb->height);
  const uint8_t* p = fb->buf;
  size_t left = fb->len;
  while (left) {
    size_t n = left > 4096 ? 4096 : left;
    Serial.write(p, n);
    p += n;
    left -= n;
  }
  Serial.flush();
  Serial.print("OK\n");
}

// Live view: newest frame, LEDs untouched, no settle/discard (fast).
static void sendLiveFrame() {
  applyExpGain(g_exposure, g_gain);
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) { Serial.println("ERR capture failed"); return; }
  sendFb(fb);
  esp_camera_fb_return(fb);
}

static camera_fb_t* captureFrame(const String& led, int exposure, int gain) {
  sensor_t* s = esp_camera_sensor_get();
  if (!s) return nullptr;

  applyExpGain(exposure, gain);

  if (!ledOnly(led)) { allLedsOff(); return nullptr; }
  delay(g_settleMs);

  // Throw away frames so exposure/LED change has fully propagated.
  for (int i = 0; i < g_discard; i++) {
    camera_fb_t* d = esp_camera_fb_get();
    if (d) esp_camera_fb_return(d);
  }
  camera_fb_t* fb = esp_camera_fb_get();
  allLedsOff();
  return fb;
}

static bool captureAndSend(const String& led, int exposure, int gain) {
  camera_fb_t* fb = captureFrame(led, exposure, gain);
  if (!fb) { Serial.println("ERR capture failed"); return false; }
  sendFb(fb);
  esp_camera_fb_return(fb);
  return true;
}

static void runBleSession() {
  g_bleStartRequested = false;
  g_bleAckNextSequence = 0;
  if (!g_bleConnected) return;
  if (!g_cameraReady) {
    setBleStatus("ERROR: camera is not ready");
    return;
  }

  g_bleSessionRunning = true;
  setBleStatus("CAPTURE_START");
  uint32_t sequence = 0;
  bool ok = true;
  for (int i = 0; i < NLED && ok; ++i) {
    const String led = LEDS[i].name;
    const int exposure = BLE_EXPOSURES[i];
    const int gain = g_gain;
    const uint8_t code = (uint8_t)i;

    setBleStatus("CAPTURE_" + led);
    camera_fb_t* lit = captureFrame(led, exposure, gain);
    if (!lit) {
      setBleStatus("ERROR: capture failed for LED " + led);
      ok = false;
      break;
    }
    ok = sendBleFrame(lit, code, code, sequence);
    esp_camera_fb_return(lit);
    if (!ok) break;

    camera_fb_t* dark = captureFrame("NONE", exposure, gain);
    if (!dark) {
      setBleStatus("ERROR: dark frame capture failed for LED " + led);
      ok = false;
      break;
    }
    ok = sendBleFrame(dark, code + 4, code + 4, sequence);
    esp_camera_fb_return(dark);
  }

  if (ok && g_bleConnected && !g_bleCancelRequested) {
    sendBleDone(sequence);
    setBleStatus("DONE");
  } else if (g_bleConnected && g_bleCancelRequested) {
    setBleStatus("CANCELLED");
  }
  allLedsOff();
  g_bleSessionRunning = false;
  // Keep the terminal notification for the current phone, while the next
  // connection/read sees a reader that can accept another test.
  if (g_bleStatus) g_bleStatus->setValue("READY");
}

// ----------------------------------------------------------------------------
static framesize_t parseRes(const String& v, bool* ok) {
  *ok = true;
  if (v == "QVGA") return FRAMESIZE_QVGA;
  if (v == "VGA")  return FRAMESIZE_VGA;
  if (v == "SVGA") return FRAMESIZE_SVGA;
  if (v == "XGA")  return FRAMESIZE_XGA;
  if (v == "SXGA") return FRAMESIZE_SXGA;
  if (v == "UXGA") return FRAMESIZE_UXGA;
  *ok = false;
  return g_res;
}

// split "A B C" into up to 4 tokens
static int tokenize(const String& line, String out[4]) {
  int n = 0, i = 0, len = line.length();
  while (i < len && n < 4) {
    while (i < len && line[i] == ' ') i++;
    if (i >= len) break;
    int j = i;
    while (j < len && line[j] != ' ') j++;
    out[n++] = line.substring(i, j);
    i = j;
  }
  return n;
}

static void handleLine(String line) {
  line.trim();
  if (!line.length()) return;
  String t[4];
  int n = tokenize(line, t);
  t[0].toUpperCase();
  const String& cmd = t[0];

  if (cmd == "PING") {
    Serial.println("OK LFAREADER 1");
  } else if (cmd == "LED" && n >= 2) {
    t[1].toUpperCase();
    Serial.println(ledOnly(t[1]) ? "OK" : "ERR bad led");
  } else if (cmd == "SET" && n >= 3) {
    String key = t[1]; key.toLowerCase();
    String val = t[2];
    if (key == "res") {
      val.toUpperCase();
      bool ok; framesize_t r = parseRes(val, &ok);
      if (ok) { g_res = r; applyRes(); Serial.println("OK"); } else Serial.println("ERR bad res");
    } else if (key == "quality")  { g_quality  = constrain(val.toInt(), 4, 63);  applyQuality(); Serial.println("OK"); }
    else if (key == "exposure")   { g_exposure = constrain(val.toInt(), 0, 1200); Serial.println("OK"); }
    else if (key == "gain")       { g_gain     = constrain(val.toInt(), 0, 30);   Serial.println("OK"); }
    else if (key == "settle")     { g_settleMs = constrain(val.toInt(), 0, 5000); Serial.println("OK"); }
    else if (key == "discard")    { g_discard  = constrain(val.toInt(), 0, 20);   Serial.println("OK"); }
    else Serial.println("ERR bad key");
  } else if (cmd == "CAP" && n >= 2) {
    t[1].toUpperCase();
    int exposure = (n >= 3) ? constrain(t[2].toInt(), 0, 1200) : g_exposure;
    int gain     = (n >= 4) ? constrain(t[3].toInt(), 0, 30)   : g_gain;
    captureAndSend(t[1], exposure, gain);
  } else if (cmd == "MASK" && n >= 2) {          // several LEDs at once: G=1 W=2 R=4 B=8
    int m = t[1].toInt();
    for (int i = 0; i < NLED; i++) ledWrite(LEDS[i].pin, ((m >> i) & 1) != 0);
    Serial.println("OK");
  } else if (cmd == "FRAME") {
    sendLiveFrame();
  } else if (cmd == "STATUS") {
    Serial.printf("OK res=%d quality=%d exposure=%d gain=%d settle=%d discard=%d\n",
                  (int)g_res, g_quality, g_exposure, g_gain, g_settleMs, g_discard);
  } else if (cmd == "BLESTATUS") {
    Serial.printf("OK BLE name=%s advertising=%d connected=%d camera=%d busy=%d service=%s\n",
                  BLE_DEVICE_NAME, (int)g_bleAdvertising, (int)g_bleConnected, (int)g_cameraReady,
                  (int)g_bleSessionRunning, BLE_SERVICE_UUID);
  } else {
    Serial.println("ERR unknown command");
  }
}

// ----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  for (int i = 0; i < NLED; i++) {
    if (LEDS[i].pin >= 0) pinMode(LEDS[i].pin, OUTPUT);
  }
  allLedsOff();

  uint32_t t0 = millis();
  while (!Serial && millis() - t0 < 3000) delay(10);

  if (!psramFound()) Serial.println("ERR PSRAM not found - set Tools > PSRAM > OPI PSRAM");
  if (!initCamera()) {
    Serial.println("ERR camera init failed - check pins in board_config.h and the FPC cable");
  } else {
    g_cameraReady = true;
    Serial.println("READY");
  }
  if (startBleService()) Serial.println("BLE ready: Kyvra-LFA");
  else Serial.println("ERR BLE advertising failed");
}

void loop() {
  if (g_bleStartRequested) runBleSession();

  static String buf;
  static uint32_t lastRx = 0;
  while (Serial.available()) {
    char ch = (char)Serial.read();
    lastRx = millis();
    if (ch == '\n' || ch == '\r') {
      if (buf.length()) { handleLine(buf); buf = ""; }
    } else if (buf.length() < 80) {
      buf += ch;
    }
  }
  // Serial Monitor set to "No line ending"? Run the command after 250 ms of silence.
  if (buf.length() && millis() - lastRx > 250) { handleLine(buf); buf = ""; }
}
