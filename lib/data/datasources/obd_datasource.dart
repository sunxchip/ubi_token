import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/obd_constants.dart';

class ObdDatasource {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;

  final _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  bool get isConnected => _device != null;

  // 주변 ELM327 장치 스캔
  Stream<List<ScanResult>> scanDevices() {
    FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
    withServices: [],);
    return FlutterBluePlus.scanResults;
    //FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    //return FlutterBluePlus.scanResults;
  }

  // 장치 연결 및 초기화
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      _device = device;

      final services = await device.discoverServices();
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeChar = char;
          }
          if (char.properties.notify) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((value) {
              final response = utf8.decode(value, allowMalformed: true);
              _dataController.add(response);
            });
          }
        }
      }

      await _initialize();
      return true;
    } catch (e) {
      return false;
    }
  }

  // AT 명령어 초기화 시퀀스
  Future<void> _initialize() async {
    final commands = [
      ObdConstants.cmdReset,
      ObdConstants.cmdEchoOff,
      ObdConstants.cmdLineFeedOff,
      ObdConstants.cmdHeaderOn,
      ObdConstants.cmdAdaptiveTiming,
      ObdConstants.cmdProtocol6,
    ];
    for (final cmd in commands) {
      await _sendCommand(cmd);
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  // 명령어 전송
  Future<void> _sendCommand(String cmd) async {
    if (_writeChar == null) return;
    await _writeChar!.write(
      utf8.encode(cmd),
      withoutResponse: _writeChar!.properties.writeWithoutResponse,
    );
  }

  // 속도 요청 (km/h)
  Future<double> getSpeed() async {
    await _sendCommand(ObdConstants.pidSpeed);
    final response = await dataStream.first
        .timeout(const Duration(seconds: 2), onTimeout: () => '');
    return _parseSpeed(response);
  }

  // RPM 요청
  Future<double> getRpm() async {
    await _sendCommand(ObdConstants.pidRpm);
    final response = await dataStream.first
        .timeout(const Duration(seconds: 2), onTimeout: () => '');
    return _parseRpm(response);
  }

  // VIN 요청
  Future<String> getVin() async {
    await _sendCommand(ObdConstants.pidVin);
    await Future.delayed(const Duration(seconds: 1));
    final response = await dataStream.first
        .timeout(const Duration(seconds: 3), onTimeout: () => '');
    return _parseVin(response);
  }

  // 속도 파싱: 41 0D XX → XX(hex) = speed
  double _parseSpeed(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      final idx = parts.indexOf('0D');
      if (idx >= 0 && idx + 1 < parts.length) {
        return int.parse(parts[idx + 1], radix: 16).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  // RPM 파싱: 41 0C A B → (A*256 + B) / 4
  double _parseRpm(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts = cleaned.split(RegExp(r'\s+'));
      final idx = parts.indexOf('0C');
      if (idx >= 0 && idx + 2 < parts.length) {
        final a = int.parse(parts[idx + 1], radix: 16);
        final b = int.parse(parts[idx + 2], radix: 16);
        return ((a * 256 + b) / 4).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  // VIN 파싱 (멀티라인 응답 조합)
  String _parseVin(String raw) {
    try {
      final hexValues = RegExp(r'[0-9A-Fa-f]{2}')
          .allMatches(raw)
          .map((m) => int.parse(m.group(0)!, radix: 16))
          .where((b) => b >= 0x20 && b <= 0x7E)
          .map((b) => String.fromCharCode(b))
          .join();
      if (hexValues.length >= 17) {
        return hexValues.substring(hexValues.length - 17);
      }
    } catch (_) {}
    return '';
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
  }

  void dispose() {
    _dataController.close();
  }
}