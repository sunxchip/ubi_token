import 'dart:async';
import 'dart:developer' as developer;
import '../models/driving_sample.dart';
import 'driving_data_source.dart';
import '../../core/utils/safe_obd_command_validator.dart';
import '../../core/utils/obd_pid_parser.dart';

/// Dry-run OBD 데이터 소스
///
/// 실제 차량에 어떤 명령도 전송하지 않는다.
/// - 허용 명령: 로그에만 기록하고 샘플 OBD 응답을 반환한다.
/// - 차단 명령: [UnsafeObdCommandException]을 발생시키고 전송하지 않는다.
///
/// 실차 연결 전 다음 항목을 검증한다:
///   1. SafeObdCommandValidator 허용 명령 정상 동작 확인
///   2. 위험 명령 10종 100% 차단 확인
///   3. ObdPidParser 샘플 응답 파싱 결과 확인
class DryRunObdDataSource implements DrivingDataSource {
  final List<DryRunLogEntry> commandLog = [];

  // ── 허용 명령 테스트 목록 ─────────────────────────────────────────────────
  static const _testCommands = [
    'ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0',
    '0100', '010C', '010D', '0111', '0104', '0902',
  ];

  // ── 차단 검증 대상 위험 명령 목록 ─────────────────────────────────────────
  static const _blockTestCommands = [
    '04',        // DTC 삭제 (절대 불가)
    '08',        // 온보드 제어 (절대 불가)
    '22F190',    // 제조사 전용 PID
    'ATSH7E0',   // CAN 헤더 설정
    'ATCRA7E8',  // CAN 수신 주소 설정
    '2E1234',    // Write Data by Identifier (ECU 쓰기)
    '1003',      // Diagnostic Session Control (UDS)
    '1101',      // ECU Reset (절대 불가)
    '14FFFFFF',  // UDS Clear DTC (절대 불가)
    '3E00',      // Tester Present
  ];

  // ── 샘플 OBD 응답 (실제 ELM327 응답 형식 준수) ───────────────────────────
  static const _sampleResponses = <String, String>{
    'ATZ':   'ELM327 v1.5',
    'ATE0':  'OK',
    'ATL0':  'OK',
    'ATS0':  'OK',
    'ATH0':  'OK',
    'ATSP0': 'OK',
    '0100':  '41 00 BE 3F A8 13',
    '010C':  '41 0C 1A F8',   // → 1726.0 rpm
    '010D':  '41 0D 28',      // → 40.0 km/h
    '0111':  '41 11 80',      // → 50.2%
    '0104':  '41 04 80',      // → 50.2%
    '0902':  '49 02 01 57 4D 49 41 44 37 32 35 32 35 36 38 30 38 33 36 37',
  };

  // ── 단일 명령 실행 ────────────────────────────────────────────────────────
  /// 명령을 검증하고 샘플 응답을 반환한다.
  /// 차단 명령이면 [UnsafeObdCommandException]을 던진다.
  /// 실제 차량에는 어떤 바이트도 전송하지 않는다.
  String runCommand(String command) {
    final normalized = command
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();

    if (!SafeObdCommandValidator.isAllowed(command)) {
      commandLog.add(DryRunLogEntry(
        command:  normalized,
        allowed:  false,
        response: null,
        parsed:   null,
      ));
      developer.log(
        '[DRY-RUN] BLOCKED: $normalized',
        name:  'DryRunObd',
        level: 900,
      );
      throw UnsafeObdCommandException(command);
    }

    final response = _sampleResponses[normalized] ?? 'NO DATA';
    final parsed   = _parseSample(normalized, response);

    commandLog.add(DryRunLogEntry(
      command:  normalized,
      allowed:  true,
      response: response,
      parsed:   parsed,
    ));

    developer.log('[DRY-RUN] allowed: $normalized',        name: 'DryRunObd');
    developer.log('[DRY-RUN] sample response: $response',  name: 'DryRunObd');
    if (parsed != null) {
      developer.log('[DRY-RUN] parsed $parsed',            name: 'DryRunObd');
    }

    return response;
  }

  String? _parseSample(String cmd, String response) {
    switch (cmd) {
      case '010C':
        final v = ObdPidParser.parseRpm(response);
        return v != null ? 'rpm: ${v.toStringAsFixed(1)}' : null;
      case '010D':
        final v = ObdPidParser.parseSpeed(response);
        return v != null ? 'speed: ${v.toStringAsFixed(1)} km/h' : null;
      case '0111':
        final v = ObdPidParser.parseThrottle(response);
        return v != null ? 'throttle: ${v.toStringAsFixed(1)}%' : null;
      case '0104':
        final v = ObdPidParser.parseEngineLoad(response);
        return v != null ? 'engineLoad: ${v.toStringAsFixed(1)}%' : null;
      default:
        return null;
    }
  }

  // ── 허용 명령 전체 Dry-run 테스트 ────────────────────────────────────────
  /// _testCommands 12개를 순서대로 검증하고 로그 반환.
  /// 실제 차량에 전송하지 않는다.
  List<DryRunLogEntry> runAllTests() {
    commandLog.clear();
    developer.log('[DRY-RUN] === runAllTests START ===', name: 'DryRunObd');
    for (final cmd in _testCommands) {
      try {
        runCommand(cmd);
      } on UnsafeObdCommandException {
        // 이미 commandLog에 blocked 항목으로 기록됨
      }
    }
    developer.log('[DRY-RUN] === runAllTests END ===', name: 'DryRunObd');
    return List.unmodifiable(commandLog);
  }

  // ── 위험 명령 차단 테스트 ─────────────────────────────────────────────────
  /// _blockTestCommands 10개가 모두 SafeObdCommandValidator에 의해 차단되는지 확인.
  /// 실제 차량에 전송하지 않는다.
  List<BlockTestResult> runBlockTests() {
    developer.log('[DRY-RUN] === runBlockTests START ===', name: 'DryRunObd');
    final results = <BlockTestResult>[];
    for (final cmd in _blockTestCommands) {
      final blocked = !SafeObdCommandValidator.isAllowed(cmd);
      results.add(BlockTestResult(command: cmd, blocked: blocked));
      developer.log(
        '[DRY-RUN] block test [$cmd] → ${blocked ? "BLOCKED ✓" : "ALLOWED ✗ DANGER!"}',
        name:  'DryRunObd',
        level: blocked ? 500 : 1000,
      );
    }
    developer.log('[DRY-RUN] === runBlockTests END ===', name: 'DryRunObd');
    return results;
  }

  // ── DrivingDataSource 구현 ────────────────────────────────────────────────
  /// 샘플 OBD 응답에서 파싱된 고정값으로 1초마다 DrivingSample을 방출한다.
  /// 실제 차량에 어떤 명령도 전송하지 않는다.
  @override
  Stream<DrivingSample> watchDrivingData(String vin) async* {
    developer.log(
      '[DRY-RUN] watchDrivingData started — no vehicle commands sent',
      name: 'DryRunObd',
    );
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        yield DrivingSample(
          timestamp:  DateTime.now(),
          speed:      ObdPidParser.parseSpeed(_sampleResponses['010D']!)      ?? 0,
          rpm:        ObdPidParser.parseRpm(_sampleResponses['010C']!)        ?? 0,
          throttle:   ObdPidParser.parseThrottle(_sampleResponses['0111']!)   ?? 0,
          engineLoad: ObdPidParser.parseEngineLoad(_sampleResponses['0104']!) ?? 0,
          vin:        vin,
        );
      } catch (e) {
        developer.log('[DRY-RUN] sample generation error: $e', name: 'DryRunObd');
      }
    }
  }

  @override
  void dispose() {
    developer.log('[DRY-RUN] disposed', name: 'DryRunObd');
  }
}

// ── 모델 ──────────────────────────────────────────────────────────────────────

/// Dry-run 명령 실행 로그 항목
class DryRunLogEntry {
  final String  command;
  final bool    allowed;
  final String? response;
  final String? parsed;
  final DateTime timestamp;

  DryRunLogEntry({
    required this.command,
    required this.allowed,
    required this.response,
    required this.parsed,
  }) : timestamp = DateTime.now();
}

/// 위험 명령 차단 테스트 결과
class BlockTestResult {
  final String command;

  /// true  = 정상적으로 차단됨 (SafeObdCommandValidator 통과 ✓)
  /// false = 차단되지 않음 (심각한 문제 — 실차 연결 금지!)
  final bool blocked;

  const BlockTestResult({required this.command, required this.blocked});
}
