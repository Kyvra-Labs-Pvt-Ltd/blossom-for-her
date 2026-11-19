import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE transport for the Kyvra ESP32-S3 reader.
///
/// Wire protocol is shared with lfa_reader/firmware/lfa_reader/lfa_reader.ino.
class LfaBleReader {
  static final Uuid serviceUuid = Uuid.parse(
    '8f9c1000-2d70-4e31-a5b2-5fa97c11a001',
  );
  static final Uuid commandUuid = Uuid.parse(
    '8f9c1001-2d70-4e31-a5b2-5fa97c11a001',
  );
  static final Uuid imageUuid = Uuid.parse(
    '8f9c1002-2d70-4e31-a5b2-5fa97c11a001',
  );
  static final Uuid statusUuid = Uuid.parse(
    '8f9c1003-2d70-4e31-a5b2-5fa97c11a001',
  );

  static const _headerSize = 21;
  static const _ackWindow = 16;
  static const _maxImageBytes = 4 * 1024 * 1024;
  static const _leds = ['G', 'W', 'R', 'B'];

  final FlutterReactiveBle _ble = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  StreamSubscription<List<int>>? _imageSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  Future<void> _packetQueue = Future<void>.value();

  Completer<void>? _connected;
  Completer<LfaCaptureSession>? _capture;
  String? _deviceId;
  ValueChanged<String>? _onProgress;
  int _nextSequence = 0;
  final Map<int, Uint8List> _buffers = {};
  final Map<int, int> _receivedBytes = {};
  final Map<String, Uint8List> _litFrames = {};
  final Map<String, Uint8List> _darkFrames = {};

  Future<List<LfaNearbyReader>> discoverReaders({
    Duration duration = const Duration(seconds: 8),
    ValueChanged<String>? onProgress,
  }) async {
    await _ensureBluetoothReady();
    onProgress?.call('Searching nearby for your Kyvra reader…');
    final found = <String, LfaNearbyReader>{};
    Object? scanError;
    final subscription = _ble
        .scanForDevices(
          withServices: [serviceUuid],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen((device) {
          found[device.id] = LfaNearbyReader(
            id: device.id,
            name: device.name.isEmpty ? 'Kyvra reader' : device.name,
            rssi: device.rssi,
          );
          onProgress?.call(
            'Found ${found.length} reader${found.length == 1 ? '' : 's'}…',
          );
        }, onError: (Object error) => scanError = error);
    try {
      await Future<void>.delayed(duration);
    } finally {
      await subscription.cancel();
    }
    if (scanError != null) {
      throw LfaReaderException(_friendlyError(scanError!));
    }
    return found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
  }

  Future<void> checkReader(String deviceId) async {
    await _ensureBluetoothReady();
    _deviceId = deviceId;
    try {
      await _connect(deviceId);
      final status = String.fromCharCodes(
        await _ble.readCharacteristic(_characteristic(statusUuid)),
      ).trim();
      if (status.startsWith('ERROR:')) {
        throw LfaReaderException(status.substring('ERROR:'.length).trim());
      }
      if (status != 'READY') {
        throw const LfaReaderException(
          'The reader is not ready. Check that it is powered on and not running another test.',
        );
      }
    } finally {
      await _disconnect();
    }
  }

  Future<LfaCaptureSession> captureSession({
    required String deviceId,
    ValueChanged<String>? onProgress,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw const LfaReaderException(
        'The reader connection is available on Android and iPhone.',
      );
    }

    _resetSession();
    _onProgress = onProgress;
    try {
      await _ensureBluetoothReady();
      _deviceId = deviceId;
      _progress('Connecting to your saved reader…');

      await _connect(deviceId);
      final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 185);
      if (mtu < 184) {
        throw LfaReaderException(
          'This phone negotiated a BLE transfer size of $mtu. The reader needs an MTU of at least 184.',
        );
      }

      final command = _characteristic(commandUuid);
      _imageSubscription = _ble
          .subscribeToCharacteristic(_characteristic(imageUuid))
          .listen(_queuePacket, onError: _fail);
      _statusSubscription = _ble
          .subscribeToCharacteristic(_characteristic(statusUuid))
          .listen(_readStatus, onError: _fail);

      final readyMessage = String.fromCharCodes(
        await _ble.readCharacteristic(_characteristic(statusUuid)),
      ).trim();
      if (readyMessage.startsWith('ERROR:')) {
        throw LfaReaderException(
          readyMessage.substring('ERROR:'.length).trim(),
        );
      }
      if (readyMessage != 'READY') {
        throw const LfaReaderException('The reader is not ready to capture.');
      }
      // Allow both notification subscriptions to finish before requesting the
      // first frame.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _capture = Completer<LfaCaptureSession>();
      _progress('Capturing four LED channels…');
      await _ble.writeCharacteristicWithResponse(
        command,
        value: Uint8List.fromList('START'.codeUnits),
      );

      return await _capture!.future.timeout(const Duration(minutes: 10));
    } on TimeoutException {
      throw const LfaReaderException(
        'The reader did not respond in time. Keep it nearby and try again.',
      );
    } catch (error) {
      if (error is LfaReaderException) rethrow;
      throw LfaReaderException(_friendlyError(error));
    } finally {
      await _disconnect();
      _onProgress = null;
    }
  }

  Future<void> dispose() => _disconnect();

  Future<void> _ensureBluetoothReady() async {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      throw const LfaReaderException(
        'The reader connection is available on Android and iPhone.',
      );
    }
    await _requestPermissions();
    var bleStatus = _ble.status;
    if (bleStatus == BleStatus.unknown) {
      bleStatus = await _ble.statusStream
          .firstWhere((status) => status != BleStatus.unknown)
          .timeout(const Duration(seconds: 10));
    }
    if (bleStatus == BleStatus.unsupported) {
      throw const LfaReaderException(
        'This phone does not support Bluetooth LE.',
      );
    }
    if (bleStatus == BleStatus.unauthorized) {
      throw const LfaReaderException(
        'Allow Bluetooth access for Kyvra, then try again.',
      );
    }
    if (bleStatus == BleStatus.poweredOff) {
      throw const LfaReaderException('Turn on Bluetooth, then try again.');
    }
    if (bleStatus == BleStatus.locationServicesDisabled) {
      throw const LfaReaderException(
        'Turn on Location Services to scan for Bluetooth devices on this Android version.',
      );
    }
    if (bleStatus != BleStatus.ready) {
      await _ble.statusStream
          .firstWhere((status) => status == BleStatus.ready)
          .timeout(const Duration(seconds: 20));
    }
  }

  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return; // iOS prompts through CoreBluetooth.
    }
    final results = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (results.values.any((status) => !status.isGranted)) {
      throw const LfaReaderException(
        'Allow Nearby Devices so the app can find your reader.',
      );
    }
  }

  Future<void> _connect(String id) async {
    _connected = Completer<void>();
    _connectionSubscription = _ble
        .connectToDevice(
          id: id,
          servicesWithCharacteristicsToDiscover: {
            serviceUuid: [commandUuid, imageUuid, statusUuid],
          },
          connectionTimeout: const Duration(seconds: 20),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !_connected!.isCompleted) {
              _connected!.complete();
            } else if (update.connectionState ==
                    DeviceConnectionState.disconnected &&
                _capture != null &&
                !_capture!.isCompleted) {
              _capture!.completeError(
                const LfaReaderException(
                  'The reader disconnected during capture.',
                ),
              );
            }
          },
          onError: (Object error) {
            if (_connected != null && !_connected!.isCompleted) {
              _connected!.completeError(error);
            }
            _fail(error);
          },
        );
    await _connected!.future;
  }

  QualifiedCharacteristic _characteristic(Uuid characteristic) =>
      QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristic,
        deviceId: _deviceId!,
      );

  void _readStatus(List<int> bytes) {
    final text = String.fromCharCodes(bytes).trim();
    if (text.startsWith('ERROR:')) {
      _fail(LfaReaderException(text.substring('ERROR:'.length).trim()));
      return;
    }
    if (text == 'DONE' || text == 'CANCELLED') return;
    if (text.startsWith('CAPTURE_')) {
      final led = text.substring('CAPTURE_'.length);
      _progress('Capturing ${_ledName(led)} image…');
    }
  }

  void _queuePacket(List<int> bytes) {
    final packet = Uint8List.fromList(bytes);
    _packetQueue = _packetQueue
        .then((_) => _handlePacket(packet))
        .catchError((Object error) => _fail(error));
  }

  Future<void> _handlePacket(Uint8List packet) async {
    if (packet.length < _headerSize || packet[0] != 0x4b || packet[1] != 0x56) {
      throw const LfaReaderException(
        'The reader sent an invalid image packet.',
      );
    }
    final type = packet[2];
    if (type == 2) {
      if (_litFrames.length != 4 || _darkFrames.length != 4) {
        throw const LfaReaderException(
          'The image transfer finished before all eight frames arrived.',
        );
      }
      if (_capture != null && !_capture!.isCompleted) {
        _progress('Choosing the clearest LED image automatically…');
        _capture!.complete(
          LfaCaptureSession(
            litFrames: Map.unmodifiable(_litFrames),
            darkFrames: Map.unmodifiable(_darkFrames),
          ),
        );
      }
      return;
    }
    if (type != 1) {
      throw const LfaReaderException('The reader reported a transfer error.');
    }

    final sequence = _readU32(packet, 3);
    if (sequence != _nextSequence) {
      throw LfaReaderException(
        'An image packet was missed (received $sequence, expected $_nextSequence).',
      );
    }
    _nextSequence++;

    final frameIndex = packet[7];
    final ledCode = packet[8];
    final totalBytes = _readU32(packet, 9);
    final offset = _readU32(packet, 13);
    if (frameIndex > 7 ||
        ledCode != frameIndex ||
        totalBytes <= 0 ||
        totalBytes > _maxImageBytes) {
      throw const LfaReaderException('The reader sent invalid image details.');
    }

    final payloadLength = packet.length - _headerSize;
    final expectedCrc = _readU32(packet, 17);
    if (_crc32(packet, _headerSize, payloadLength) != expectedCrc) {
      throw const LfaReaderException(
        'An image chunk failed its integrity check.',
      );
    }
    final expectedOffset = _receivedBytes[frameIndex] ?? 0;
    if (offset != expectedOffset || offset + payloadLength > totalBytes) {
      throw const LfaReaderException('An image frame arrived out of order.');
    }
    final buffer = _buffers.putIfAbsent(
      frameIndex,
      () => Uint8List(totalBytes),
    );
    if (buffer.length != totalBytes) {
      throw const LfaReaderException(
        'An image frame changed size mid-transfer.',
      );
    }
    buffer.setRange(offset, offset + payloadLength, packet, _headerSize);
    final received = offset + payloadLength;
    _receivedBytes[frameIndex] = received;
    if (received == totalBytes) {
      final led = _leds[frameIndex % 4];
      if (frameIndex < 4) {
        _litFrames[led] = buffer;
      } else {
        _darkFrames[led] = buffer;
      }
      _progress('Received ${_ledName(led)} channel (${_litFrames.length}/4)…');
    }

    if (_nextSequence % _ackWindow == 0) {
      final ack = Uint8List(5)
        ..[0] = 0xac
        ..[1] = _nextSequence & 0xff
        ..[2] = (_nextSequence >> 8) & 0xff
        ..[3] = (_nextSequence >> 16) & 0xff
        ..[4] = (_nextSequence >> 24) & 0xff;
      await _ble.writeCharacteristicWithResponse(
        _characteristic(commandUuid),
        value: ack,
      );
    }
  }

  int _readU32(List<int> data, int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);

  int _crc32(List<int> data, int start, int length) {
    var crc = 0xffffffff;
    for (var i = start; i < start + length; i++) {
      crc ^= data[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    return (~crc) & 0xffffffff;
  }

  void _fail(Object error) {
    if (_capture != null && !_capture!.isCompleted) {
      _capture!.completeError(
        error is LfaReaderException
            ? error
            : LfaReaderException(_friendlyError(error)),
      );
    }
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('unauthorized')) {
      return 'Allow Bluetooth access for Kyvra, then try again.';
    }
    if (message.contains('poweredOff')) {
      return 'Turn on Bluetooth, then try again.';
    }
    if (message.contains('locationServicesDisabled')) {
      return 'Turn on Location Services to scan for Bluetooth devices on this Android version.';
    }
    return 'Could not connect to the reader: $message';
  }

  void _progress(String value) => _onProgress?.call(value);

  String _ledName(String led) => switch (led) {
    'G' => 'green',
    'W' => 'white',
    'R' => 'red',
    'B' => 'blue',
    _ => led,
  };

  void _resetSession() {
    _nextSequence = 0;
    _buffers.clear();
    _receivedBytes.clear();
    _litFrames.clear();
    _darkFrames.clear();
    _capture = null;
    _packetQueue = Future<void>.value();
  }

  Future<void> _disconnect() async {
    await _imageSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _connectionSubscription?.cancel();
    _imageSubscription = null;
    _statusSubscription = null;
    _connectionSubscription = null;
    _deviceId = null;
  }
}

class LfaNearbyReader {
  final String id;
  final String name;
  final int rssi;

  const LfaNearbyReader({
    required this.id,
    required this.name,
    required this.rssi,
  });
}

class LfaSavedReader {
  final String id;
  final String name;

  const LfaSavedReader({required this.id, required this.name});
}

class LfaReaderStore {
  static const MethodChannel _channel = MethodChannel('blossom/reader_store');

  static Future<LfaSavedReader?> load() async {
    final value = await _channel.invokeMapMethod<String, dynamic>('loadReader');
    if (value == null || value['id'] is! String) return null;
    return LfaSavedReader(
      id: value['id'] as String,
      name: value['name'] is String ? value['name'] as String : 'Kyvra reader',
    );
  }

  static Future<void> save(LfaNearbyReader reader) => _channel
      .invokeMethod<void>('saveReader', {'id': reader.id, 'name': reader.name});

  static Future<void> forget() => _channel.invokeMethod<void>('forgetReader');
}

class LfaCaptureSession {
  final Map<String, Uint8List> litFrames;
  final Map<String, Uint8List> darkFrames;

  const LfaCaptureSession({required this.litFrames, required this.darkFrames});
}

class LfaReaderException implements Exception {
  final String message;
  const LfaReaderException(this.message);

  @override
  String toString() => message;
}

class LfaChannelSelection {
  final String led;
  final Uint8List image;
  final double score;
  final Map<String, double> scores;

  const LfaChannelSelection({
    required this.led,
    required this.image,
    required this.score,
    required this.scores,
  });
}

/// Ranks the four LED images locally. It uses dark-corrected line-profile
/// prominence plus sharpness and clipping; no image is uploaded anywhere.
class LfaImageSelector {
  static const _channelIndex = {'G': 1, 'W': 1, 'R': 0, 'B': 2};

  static Future<LfaChannelSelection> choose(LfaCaptureSession session) async {
    final scores = <String, double>{};
    for (final led in LfaBleReader._leds) {
      final lit = session.litFrames[led];
      final dark = session.darkFrames[led];
      if (lit == null || dark == null) {
        throw const LfaReaderException('One of the LED images is missing.');
      }
      scores[led] = await _score(led, lit, dark);
    }
    final selected = scores.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    );
    return LfaChannelSelection(
      led: selected.key,
      image: session.litFrames[selected.key]!,
      score: selected.value,
      scores: Map.unmodifiable(scores),
    );
  }

  static Future<double> _score(
    String led,
    Uint8List litBytes,
    Uint8List darkBytes,
  ) async {
    final litCodec = await ui.instantiateImageCodec(litBytes);
    final darkCodec = await ui.instantiateImageCodec(darkBytes);
    final litFrame = await litCodec.getNextFrame();
    final darkFrame = await darkCodec.getNextFrame();
    final litImage = litFrame.image;
    final darkImage = darkFrame.image;
    try {
      if (litImage.width != darkImage.width ||
          litImage.height != darkImage.height) {
        throw const LfaReaderException(
          'Lit and dark image sizes do not match.',
        );
      }
      final lit = await litImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      final dark = await darkImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (lit == null || dark == null) {
        throw const LfaReaderException(
          'The reader image could not be decoded.',
        );
      }
      final width = litImage.width;
      final height = litImage.height;
      final channel = _channelIndex[led]!;
      final horizontal = _lineProfileScore(
        lit,
        dark,
        width,
        height,
        channel,
        true,
      );
      final vertical = _lineProfileScore(
        lit,
        dark,
        width,
        height,
        channel,
        false,
      );
      final imageQuality = _imageQuality(lit, width, height, channel);
      return math.max(horizontal, vertical).toDouble() + imageQuality;
    } finally {
      litImage.dispose();
      darkImage.dispose();
      litCodec.dispose();
      darkCodec.dispose();
    }
  }

  static double _lineProfileScore(
    ByteData lit,
    ByteData dark,
    int width,
    int height,
    int channel,
    bool horizontal,
  ) {
    final along = horizontal ? width : height;
    final across = horizontal ? height : width;
    final bins = math.min(along, 512).toInt();
    final acrossStart = (across * 0.28).round();
    final acrossEnd = (across * 0.72).round();
    final acrossStep = math.max(1, (acrossEnd - acrossStart) ~/ 96).toInt();
    final profile = List<double>.filled(bins, 0);

    for (var bin = 0; bin < bins; bin++) {
      final alongPosition = ((bin + 0.5) * along / bins)
          .floor()
          .clamp(0, along - 1)
          .toInt();
      var litSum = 0.0;
      var darkSum = 0.0;
      var samples = 0;
      for (var cross = acrossStart; cross < acrossEnd; cross += acrossStep) {
        final x = horizontal ? alongPosition : cross;
        final y = horizontal ? cross : alongPosition;
        final index = (y * width + x) * 4 + channel;
        litSum += lit.getUint8(index);
        darkSum += dark.getUint8(index);
        samples++;
      }
      profile[bin] = math
          .max(1.0, (litSum - darkSum) / math.max(1, samples))
          .toDouble();
    }

    if (profile.length < 24) return 0;
    final radius = math.max(3, profile.length ~/ 100).toInt();
    final outer = radius * 3;
    final residual = List<double>.filled(profile.length, 0);
    for (var i = 0; i < profile.length; i++) {
      var sum = 0.0;
      var count = 0;
      for (var j = math.max(0, i - outer).toInt(); j <= i - radius; j++) {
        sum += profile[j];
        count++;
      }
      for (
        var j = i + radius;
        j <= math.min(profile.length - 1, i + outer).toInt();
        j++
      ) {
        sum += profile[j];
        count++;
      }
      if (count > 0) residual[i] = sum / count - profile[i];
    }

    final sortedResidual = [...residual]..sort();
    final median = sortedResidual[sortedResidual.length ~/ 2];
    final deviations = residual.map((value) => (value - median).abs()).toList()
      ..sort();
    final noise = math
        .max(0.5, 1.4826 * deviations[deviations.length ~/ 2])
        .toDouble();
    final threshold = math.max(1.5, 3.0 * noise).toDouble();
    final candidates = <(int, double)>[];
    for (var i = 2; i < residual.length - 2; i++) {
      if (residual[i] >= threshold &&
          residual[i] >= residual[i - 1] &&
          residual[i] > residual[i + 1]) {
        candidates.add((i, residual[i]));
      }
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    final minDistance = math.max(6, profile.length ~/ 70).toInt();
    final selected = <(int, double)>[];
    for (final candidate in candidates) {
      if (selected.every(
        (item) => (item.$1 - candidate.$1).abs() >= minDistance,
      )) {
        selected.add(candidate);
        if (selected.length == 2) break;
      }
    }
    return selected.fold<double>(
      0,
      (sum, peak) => sum + 7.0 + math.min(20.0, peak.$2 / noise).toDouble(),
    );
  }

  static double _imageQuality(
    ByteData pixels,
    int width,
    int height,
    int channel,
  ) {
    final x0 = (width * 0.12).round();
    final x1 = (width * 0.88).round();
    final y0 = (height * 0.12).round();
    final y1 = (height * 0.88).round();
    final step = math.max(2, math.min(width, height) ~/ 180).toInt();
    var sum = 0.0;
    var sumSquares = 0.0;
    var clipped = 0;
    var samples = 0;
    var laplaceSquares = 0.0;
    var laplaceSamples = 0;

    for (var y = y0 + step; y < y1 - step; y += step) {
      for (var x = x0 + step; x < x1 - step; x += step) {
        int pixel(int px, int py) =>
            pixels.getUint8((py * width + px) * 4 + channel);
        final value = pixel(x, y).toDouble();
        sum += value;
        sumSquares += value * value;
        if (value <= 3 || value >= 252) clipped++;
        samples++;
        final lap =
            4 * value -
            pixel(x - step, y) -
            pixel(x + step, y) -
            pixel(x, y - step) -
            pixel(x, y + step);
        laplaceSquares += lap * lap;
        laplaceSamples++;
      }
    }
    if (samples == 0) return 0;
    final mean = sum / samples;
    final variance = math
        .max(0.0, sumSquares / samples - mean * mean)
        .toDouble();
    final focus = math
        .min(8.0, math.log(1 + laplaceSquares / math.max(1, laplaceSamples)))
        .toDouble();
    final contrast = math.sqrt(variance) / 32;
    final clippingPenalty = 25 * clipped / samples;
    return focus + contrast - clippingPenalty;
  }
}
