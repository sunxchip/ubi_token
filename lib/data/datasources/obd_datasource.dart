import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/obd_constants.dart';
import '../../core/utils/safe_obd_command_validator.dart';

class ObdDatasource {
  // ── 전역 연결 인스턴스 ─────────────────────────────────
  static ObdDatasource? _connected;
  static ObdDatasource? get connected => _connected;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;

  final _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  // ── 명령 직렬화 락 ────────────────────────────────────
  bool _commandBusy = false;

  Future<T> _withLock<T>(Future<T> Function() fn) async {
    int waited = 0;
    while (_commandBusy && waited < 2000) {
      await Future.delayed(const Duration(milliseconds: 20));
      waited += 20;
    }
    _commandBusy = true;
    try {
      return await fn();
    } finally {
      _commandBusy = false;
    }
  }

  bool get isConnected => _device != null;
  String get deviceName => _device?.platformName ?? '';

  // ── 디바이스 ID 영속화 ─────────────────────────────────
  static Future<void> saveLastDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ble_device_id', deviceId);
  }

  static Future<String?> loadLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_ble_device_id');
  }

  // ── 스캔 ───────────────────────────────────────────────
  Stream<List<ScanResult>> scanDevices() {
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [],
    );
    return FlutterBluePlus.scanResults;
  }

  // ── 연결 ───────────────────────────────────────────────
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );
      _device = device;

      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (ObdDatasource._connected == this) {
            ObdDatasource._connected = null;
          }
          _device    = null;
          _writeChar = null;
        }
      });

      final services = await device.discoverServices();
      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeChar = char;
          }
          if (char.properties.notify) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((value) {
              if (value.isEmpty) return;
              if (_dataController.isClosed) return;
              final response = utf8.decode(value, allowMalformed: true);
              _dataController.add(response);
            });
          }
        }
      }

      await _initialize();
      await saveLastDeviceId(device.remoteId.str);

      ObdDatasource._connected = this;
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── AT 초기화 (표준 읽기 전용 명령만 사용) ───────────
  Future<void> _initialize() async {
    final commands = [
      ObdConstants.cmdReset,        // ATZ
      ObdConstants.cmdEchoOff,      // ATE0
      ObdConstants.cmdLineFeedOff,  // ATL0
      ObdConstants.cmdSpacesOff,    // ATS0
      ObdConstants.cmdHeaderOff,    // ATH0  (헤더 OFF - Raw CAN 접근 불가)
      ObdConstants.cmdProtocolAuto, // ATSP0
    ];
    for (final cmd in commands) {
      await _sendRawBytes(cmd);
      await Future.delayed(const Duration(milliseconds: 300));
    }
  }

  // ── 내부 전용: BLE 바이트 전송 (검증 없음, 초기화·PID 전용) ──
  Future<void> _sendRawBytes(String cmd) async {
    if (_writeChar == null) return;
    await _writeChar!.write(
      utf8.encode(cmd),
      withoutResponse: _writeChar!.properties.writeWithoutResponse,
    );
  }

  // ── 공개 명령 전송 (SafeObdCommandValidator 필수 통과) ──
  //
  // 허용 목록에 없는 명령은 차량에 절대 전송하지 않는다.
  // PID 진단 화면 터미널에서만 사용한다.
  Future<String> sendCommand(String cmd, {int maxLines = 3}) {
    SafeObdCommandValidator.assertSafe(cmd); // 차단 시 UnsafeObdCommandException 발생
    return _withLock(() async {
      final buffer    = StringBuffer();
      final completer = Completer<String>();
      late StreamSubscription<String> sub;

      sub = dataStream.listen((data) {
        buffer.write(data);
        final raw = buffer.toString();
        if (raw.contains('>') && !completer.isCompleted) {
          sub.cancel();
          completer.complete(raw);
        }
      });

      final rawCmd = cmd.endsWith('\r') ? cmd : '$cmd\r';
      await _sendRawBytes(rawCmd);

      return completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          sub.cancel();
          return buffer.toString().isEmpty ? '(응답 없음)' : buffer.toString();
        },
      );
    });
  }

  // ── 표준 OBD PID 읽기 (응답 대기) ─────────────────────
  Future<String> _requestPid(String cmd,
      {Duration timeout = const Duration(seconds: 2)}) {
    return _withLock(() async {
      final buffer    = StringBuffer();
      final completer = Completer<String>();
      late StreamSubscription<String> sub;

      sub = dataStream.listen((data) {
        buffer.write(data);
        if (buffer.toString().contains('>') && !completer.isCompleted) {
          sub.cancel();
          completer.complete(buffer.toString());
        }
      });

      await _sendRawBytes(cmd);

      return completer.future.timeout(
        timeout,
        onTimeout: () {
          sub.cancel();
          return buffer.toString();
        },
      );
    });
  }

  // ── 속도 (km/h) ────────────────────────────────────────
  Future<double> getSpeed() async {
    final response = await _requestPid(ObdConstants.pidSpeed);
    return _parseSpeed(response);
  }

  // ── RPM ────────────────────────────────────────────────
  Future<double> getRpm() async {
    final response = await _requestPid(ObdConstants.pidRpm);
    return _parseRpm(response);
  }

  // ── 스로틀 위치 (0~100%) ────────────────────────────────
  Future<double> getThrottle() async {
    final response = await _requestPid(ObdConstants.pidThrottlePosition);
    return _parsePercent(response, '11');
  }

  // ── 엔진 부하 (0~100%) ─────────────────────────────────
  Future<double> getEngineLoad() async {
    final response = await _requestPid(ObdConstants.pidEngineLoad);
    return _parsePercent(response, '04');
  }

  // ── VIN ────────────────────────────────────────────────
  Future<String> getVin() async {
    final buffer    = StringBuffer();
    final completer = Completer<String>();
    late StreamSubscription<String> sub;

    sub = dataStream.listen((data) {
      buffer.write(data);
      if (buffer.toString().contains('>') && !completer.isCompleted) {
        sub.cancel();
        completer.complete(_parseVin(buffer.toString()));
      }
    });

    await _sendRawBytes(ObdConstants.pidVin);

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub.cancel();
        return _parseVin(buffer.toString());
      },
    );
  }

  // ── 파싱: 속도 ────────────────────────────────────────
  double _parseSpeed(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts   = cleaned.split(RegExp(r'\s+'));
      final idx     = parts.indexOf('0D');
      if (idx >= 0 && idx + 1 < parts.length) {
        return int.parse(parts[idx + 1], radix: 16).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  // ── 파싱: RPM ─────────────────────────────────────────
  double _parseRpm(String raw) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts   = cleaned.split(RegExp(r'\s+'));
      final idx     = parts.indexOf('0C');
      if (idx >= 0 && idx + 2 < parts.length) {
        final a = int.parse(parts[idx + 1], radix: 16);
        final b = int.parse(parts[idx + 2], radix: 16);
        return ((a * 256 + b) / 4).toDouble();
      }
    } catch (_) {}
    return 0.0;
  }

  // ── 파싱: 퍼센트 PID (스로틀/엔진부하) ────────────────
  // 응답 공식: A × 100 / 255  (%)
  double _parsePercent(String raw, String pidHex) {
    try {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9A-Fa-f\s]'), '').trim();
      final parts   = cleaned.split(RegExp(r'\s+'));
      final idx     = parts.indexOf(pidHex.toUpperCase());
      if (idx >= 0 && idx + 1 < parts.length) {
        final a = int.parse(parts[idx + 1], radix: 16);
        return a * 100.0 / 255.0;
      }
    } catch (_) {}
    return 0.0;
  }

  // ── 파싱: VIN (ISO 15765 멀티프레임, ATH0/ATH1 모두 지원) ──
  //
  // ATH1 응답 (헤더 ON): "7E8 10 LL 49 02 01 B0 B1 B2"
  // ATH0 응답 (헤더 OFF): "10 LL 49 02 01 B0 B1 B2"
  String _parseVin(String raw) {
    try {
      final vinBytes = <int>[];

      for (final line in raw.split(RegExp(r'[\r\n]+'))) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 2) continue;

        int frameCtrl;
        int dataStart;

        if (RegExp(r'^[0-9A-Fa-f]{3}$').hasMatch(parts[0])) {
          // ATH1: 3자리 CAN ID 존재 (예: 7E8)
          if (parts.length < 3) continue;
          frameCtrl = int.tryParse(parts[1], radix: 16) ?? 0;
          dataStart  = 2;
        } else if (RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(parts[0])) {
          // ATH0: CAN ID 없음, 첫 바이트가 프레임 제어
          frameCtrl = int.tryParse(parts[0], radix: 16) ?? 0;
          dataStart  = 1;
        } else {
          continue;
        }

        if ((frameCtrl & 0xF0) == 0x10) {
          // 첫 번째 프레임: length, mode(49), PID(02), counter(01) 건너뜀
          for (int i = dataStart + 4; i < parts.length; i++) {
            final b = int.tryParse(parts[i], radix: 16) ?? 0;
            if (b != 0) vinBytes.add(b);
          }
        } else if ((frameCtrl & 0xF0) == 0x20) {
          // 연속 프레임
          for (int i = dataStart; i < parts.length; i++) {
            final b = int.tryParse(parts[i], radix: 16) ?? 0;
            if (b != 0) vinBytes.add(b);
          }
        }
      }

      if (vinBytes.isNotEmpty) {
        final vinStr = vinBytes
            .where((b) => b >= 0x20 && b <= 0x7E)
            .map((b) => String.fromCharCode(b))
            .join();
        final match = RegExp(r'[A-HJ-NPR-Z0-9]{17}').firstMatch(vinStr);
        if (match != null) return match.group(0)!;
        if (vinStr.length >= 17) return vinStr.substring(0, 17);
      }

      // 폴백: 연속 hex 바이트에서 ASCII 추출 후 VIN 패턴 탐색
      final allHex = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
      final fbBytes = <int>[];
      for (int i = 0; i + 1 < allHex.length; i += 2) {
        final b = int.tryParse(allHex.substring(i, i + 2), radix: 16) ?? 0;
        if (b >= 0x20 && b <= 0x7E) fbBytes.add(b);
      }
      final fbStr   = String.fromCharCodes(fbBytes);
      final fbMatch = RegExp(r'[A-HJ-NPR-Z0-9]{17}').firstMatch(fbStr);
      if (fbMatch != null) return fbMatch.group(0)!;
    } catch (e) {
      developer.log('VIN parse error: $e', name: 'ObdDatasource');
    }
    return '';
  }

  // ── 연결 해제 ──────────────────────────────────────────
  Future<void> disconnect() async {
    if (ObdDatasource._connected == this) {
      ObdDatasource._connected = null;
    }
    await _device?.disconnect();
    _device    = null;
    _writeChar = null;
  }

  void dispose() {
    if (ObdDatasource._connected != this) {
      _dataController.close();
    }
  }
}
