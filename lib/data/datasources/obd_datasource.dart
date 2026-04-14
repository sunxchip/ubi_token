import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/obd_constants.dart';

class TurnSignalState {
  final bool left;
  final bool right;
  final bool hazard;
  const TurnSignalState({
    required this.left,
    required this.right,
    required this.hazard,
  });
}

class ObdDatasource {
  // ── 전역 연결 인스턴스 ─────────────────────────────────
  static ObdDatasource? _connected;
  static ObdDatasource? get connected => _connected;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _writeChar;

  final _dataController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataController.stream;

  // ── 명령 직렬화 락 ────────────────────────────────────
  // 대시보드 폴링 + 진단 화면 동시 명령 전송 시 충돌 방지
  bool _commandBusy = false;

  Future<T> _withLock<T>(Future<T> Function() fn) async {
    // 이전 명령이 끝날 때까지 대기 (최대 2초)
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

      // BLE 연결 상태 감시: 끊기면 전역 인스턴스 자동 해제
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (ObdDatasource._connected == this) {
            ObdDatasource._connected = null;
          }
          _device   = null;
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
              if (_dataController.isClosed) return; // 컨트롤러 닫힌 후 콜백 방어
              final response = utf8.decode(value, allowMalformed: true);
              _dataController.add(response);
            });
          }
        }
      }

      await _initialize();
      await saveLastDeviceId(device.remoteId.str);

      // 전역 연결 인스턴스로 등록
      ObdDatasource._connected = this;
      return true;
    } catch (e) {
      return false;
    }
  }

  // ── AT 초기화 ──────────────────────────────────────────
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

  // ── 명령 전송 ──────────────────────────────────────────
  Future<void> _sendCommand(String cmd) async {
    if (_writeChar == null) return;
    await _writeChar!.write(
      utf8.encode(cmd),
      withoutResponse: _writeChar!.properties.writeWithoutResponse,
    );
  }

  // ── 진단용 raw 명령 전송 (응답 반환) ──────────────────
  // ATMA 명령은 '>'가 오지 않으므로 maxLines 줄 수신 후 자동 중단
  Future<String> sendRaw(String cmd, {int maxLines = 3}) {
    return _withLock(() async {
      final isMonitor = cmd.trim().toUpperCase() == 'ATMA';
      final buffer    = StringBuffer();
      final completer = Completer<String>();
      late StreamSubscription<String> sub;

      sub = dataStream.listen((data) {
        buffer.write(data);
        final raw = buffer.toString();
        final done = raw.contains('>') ||
            (isMonitor && raw.split('\n').where((l) => l.trim().isNotEmpty).length >= maxLines);
        if (done && !completer.isCompleted) {
          sub.cancel();
          completer.complete(raw);
        }
      });

      final rawCmd = cmd.endsWith('\r') ? cmd : '$cmd\r';
      await _sendCommand(rawCmd);

      final result = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          sub.cancel();
          return buffer.toString().isEmpty ? '(응답 없음)' : buffer.toString();
        },
      );

      // ATMA 후 자동 중단: 임의 문자 전송
      if (isMonitor) await _stopMonitor();

      return result;
    });
  }

  // ── 표준 OBD PID 읽기 (응답 대기) ─────────────────────
  Future<String> _requestPid(String cmd, {Duration timeout = const Duration(seconds: 2)}) {
    return _withLock(() async {
      final buffer = StringBuffer();
      final completer = Completer<String>();
      late StreamSubscription<String> sub;

      sub = dataStream.listen((data) {
        buffer.write(data);
        if (buffer.toString().contains('>') && !completer.isCompleted) {
          sub.cancel();
          completer.complete(buffer.toString());
        }
      });

      await _sendCommand(cmd);

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

  // ── VIN ────────────────────────────────────────────────
  Future<String> getVin() async {
    final buffer = StringBuffer();
    final completer = Completer<String>();
    late StreamSubscription<String> sub;

    sub = dataStream.listen((data) {
      buffer.write(data);
      if (buffer.toString().contains('>') && !completer.isCompleted) {
        sub.cancel();
        completer.complete(_parseVin(buffer.toString()));
      }
    });

    await _sendCommand(ObdConstants.pidVin);

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        sub.cancel();
        return _parseVin(buffer.toString());
      },
    );
  }

  // ── 조향각 (아반떼 AD 전용, 0x2B0) ────────────────────
  // ⚠ 비공개 PID - 실차 검증 필수. 파싱 방식이 다르면 수정 필요.
  // CAN 필터로 0x2B0 프레임 1개 캡처: "2B0 HH LL XX XX XX XX XX XX"
  // byte 0-1: signed 16-bit big-endian, ÷10 = 조향각(도)
  Future<double> getSteeringAngle() async {
    return _readCanFrame(
      canId: ObdConstants.canIdSteering,
      parse: _parseSteeringAngle,
    );
  }

  // ── 방향지시등 + 비상등 (아반떼 AD 전용, 0x4B0) ────────
  // ⚠ 비공개 PID - 실차 검증 필수.
  // CAN 필터로 0x4B0 프레임 1개 캡처: "4B0 BB XX XX XX XX XX XX XX"
  // byte 0: bit0=좌, bit1=우 (커뮤니티 RE 기반, 실차 확인 필요)
  Future<TurnSignalState> getTurnSignals() async {
    final raw = await _readCanFrame<String>(
      canId: ObdConstants.canIdBcm,
      parse: (r) => r,
    );
    return _parseTurnSignals(raw);
  }

  // ── CAN 필터 + ATMA 방식으로 단일 프레임 캡처 ─────────
  Future<T> _readCanFrame<T>({
    required String canId,
    required T Function(String) parse,
  }) {
    return _withLock(() async {
    // 1. CAN 필터 설정
    await _sendCommand('ATCAF0\r'); // 자동 포맷 OFF (raw 프레임)
    await Future.delayed(const Duration(milliseconds: 50));
    await _sendCommand('ATCF $canId\r'); // 특정 CAN ID 필터
    await Future.delayed(const Duration(milliseconds: 50));
    await _sendCommand('ATCM FFF\r'); // 정확히 일치하는 ID만
    await Future.delayed(const Duration(milliseconds: 50));

    // 2. ATMA로 모니터링 시작, 프레임 1개 수신
    final buffer = StringBuffer();
    final completer = Completer<String>();
    late StreamSubscription<String> sub;

    sub = dataStream.listen((data) {
      buffer.write(data);
      final raw = buffer.toString();
      // 헤더가 포함된 라인이 오면 캡처 완료
      if ((raw.contains(canId.toUpperCase()) || raw.contains(canId.toLowerCase()))
          && !completer.isCompleted) {
        sub.cancel();
        completer.complete(raw);
      }
    });

    await _sendCommand('ATMA\r');

    final frame = await completer.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        sub.cancel();
        return buffer.toString();
      },
    );

    // 3. ATMA 중단 (ELM327: 임의 문자 전송 시 모니터 중단)
    await _stopMonitor();

    // 4. 일반 OBD 모드 복원
    await _restoreObd();

    return parse(frame);
    });
  }

  Future<void> _stopMonitor() async {
    if (_writeChar == null) return;
    // ATMA 중단: 임의 문자 전송
    await _writeChar!.write(
      utf8.encode(' '),
      withoutResponse: _writeChar!.properties.writeWithoutResponse,
    );
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<void> _restoreObd() async {
    // CAN 필터 초기화 → 일반 OBD 모드 복원
    await _sendCommand('ATCAF1\r'); // 자동 포맷 ON
    await Future.delayed(const Duration(milliseconds: 30));
    await _sendCommand('ATCF 000\r'); // 필터 초기화
    await Future.delayed(const Duration(milliseconds: 30));
    await _sendCommand('ATCM 000\r'); // 마스크 초기화
    await Future.delayed(const Duration(milliseconds: 30));
  }

  // ── 파싱: 속도 ────────────────────────────────────────
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

  // ── 파싱: RPM ─────────────────────────────────────────
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

  // ── 파싱: VIN ─────────────────────────────────────────
  // ISO 15765 멀티프레임 구조를 직접 파싱해 CAN 헤더를 완전히 제거
  //
  // ATH1 응답 형식:
  //   첫 번째 프레임: "7E8 10 LL 49 02 01 B0 B1 B2"
  //                         ^프레임타입 ^길이 ^모드 ^PID ^카운트 ^VIN바이트
  //   연속 프레임:    "7E8 2X B0 B1 B2 B3 B4 B5 B6"
  //                         ^연속번호   ^VIN바이트
  String _parseVin(String raw) {
    try {
      final vinBytes = <int>[];

      for (final line in raw.split(RegExp(r'[\r\n]+'))) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length < 3) continue;

        // 첫 토큰이 3자리 hex(CAN ID)인 줄만 처리
        if (!RegExp(r'^[0-9A-Fa-f]{3}$').hasMatch(parts[0])) continue;

        final frameCtrl = int.tryParse(parts[1], radix: 16) ?? 0;

        if ((frameCtrl & 0xF0) == 0x10) {
          // 첫 번째 프레임: 인덱스 0=CAN, 1=10, 2=LL, 3=49, 4=02, 5=01, 6부터 VIN
          for (int i = 6; i < parts.length; i++) {
            final b = int.tryParse(parts[i], radix: 16) ?? 0;
            if (b != 0) vinBytes.add(b);
          }
        } else if ((frameCtrl & 0xF0) == 0x20) {
          // 연속 프레임: 인덱스 0=CAN, 1=연속번호, 2부터 VIN
          for (int i = 2; i < parts.length; i++) {
            final b = int.tryParse(parts[i], radix: 16) ?? 0;
            if (b != 0) vinBytes.add(b);
          }
        }
      }

      final vinStr = vinBytes
          .where((b) => b >= 0x20 && b <= 0x7E)
          .map((b) => String.fromCharCode(b))
          .join();

      // VIN 표준 패턴 (I/O/Q 제외, 17자)
      final match = RegExp(r'[A-HJ-NPR-Z0-9]{17}').firstMatch(vinStr);
      if (match != null) return match.group(0)!;

      if (vinStr.length >= 17) return vinStr.substring(0, 17);
    } catch (_) {}
    return '';
  }

  // ── 파싱: 조향각 ──────────────────────────────────────
  // SAS11 (0x2B0 = 688) openpilot DBC 기반 실차 검증 결과:
  //   byte0-1: signed 16-bit little-endian ÷10 = 조향각(°)
  //            센터 오프셋 존재 (직진 시 약 -366°, ECU 캘리브레이션값)
  //   byte2  : unsigned 8-bit × 4 = 조향 각속도(°/s)
  //   byte3  : SAS 상태 (고정값)
  //
  // 부호 규칙: 좌회전 = 값 증가, 우회전 = 값 감소
  // 스코어링에서는 delta/time을 사용하므로 센터 오프셋은 자동 상쇄
  double _parseSteeringAngle(String raw) {
    try {
      final lines = raw.split(RegExp(r'[\r\n]'));
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty &&
            parts[0].toUpperCase() == ObdConstants.canIdSteering.toUpperCase() &&
            parts.length >= 3) {
          // little-endian: parts[1]=byte0(low), parts[2]=byte1(high)
          final low  = int.parse(parts[1], radix: 16);
          final high = int.parse(parts[2], radix: 16);
          int raw16 = (high << 8) | low;
          if (raw16 > 32767) raw16 -= 65536; // signed
          return raw16 / 10.0;
        }
      }
    } catch (_) {}
    return 0.0;
  }

  // ── 파싱: 방향지시등 ──────────────────────────────────
  // 응답 예: "4B0 03 00 00 00 00 00 00 00"
  // byte0: bit0=좌회전, bit1=우회전 (커뮤니티 RE 기반)
  // ⚠ 실차에서 검증 후 비트 위치 조정 필요
  // 0x386 프레임 구조 (실차 검증):
  // parts: [386] [B0] [B1] [B2] [B3] ...
  //  인덱스:  0    1    2    3    4
  // 우회전: parts[2] (byte1) bit7 (0x80) 토글 ← 검증 완료
  // 좌회전: ⚠ 미검증 - 테스트 후 turnLeftMask/byteIndex 업데이트 필요
  TurnSignalState _parseTurnSignals(String raw) {
    try {
      final lines = raw.split(RegExp(r'[\r\n]'));
      for (final line in lines) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty &&
            parts[0].toUpperCase() == ObdConstants.canIdBcm.toUpperCase() &&
            parts.length >= 5) {
          final byte1 = int.parse(parts[2], radix: 16); // byte1
          final right  = (byte1 & ObdConstants.turnRightMask) != 0;
          // 좌회전 마스크가 0x00이면 항상 false (미검증 상태)
          final left = ObdConstants.turnLeftMask != 0x00
              ? (byte1 & ObdConstants.turnLeftMask) != 0
              : false;
          final hazard = left && right;
          return TurnSignalState(
            left:   left && !hazard,
            right:  right && !hazard,
            hazard: hazard,
          );
        }
      }
    } catch (_) {}
    return const TurnSignalState(left: false, right: false, hazard: false);
  }

  // ── 연결 해제 ──────────────────────────────────────────
  Future<void> disconnect() async {
    if (ObdDatasource._connected == this) {
      ObdDatasource._connected = null;
    }
    await _device?.disconnect();
    _device = null;
    _writeChar = null;
  }

  void dispose() {
    // 전역 연결 인스턴스로 등록된 경우 스트림을 닫지 않음
    if (ObdDatasource._connected != this) {
      _dataController.close();
    }
  }
}
