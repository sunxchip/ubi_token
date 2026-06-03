import 'dart:async';
import 'dart:developer' as developer;
import '../models/driving_sample.dart';
import '../models/obd_drive_log.dart';
import 'driving_data_source.dart';
import 'obd_datasource.dart';
import '../../core/utils/safe_obd_command_validator.dart';
import '../../core/utils/obd_pid_parser.dart';

// ── 정차 테스트 결과 ───────────────────────────────────────────────────────────
class StationaryTestResult {
  final bool              passed;
  final List<ObdDriveLog> logs;
  final String?           error;
  const StationaryTestResult({
    required this.passed,
    required this.logs,
    this.error,
  });
}

/// 표준 PID 읽기 전용 실차 데이터 소스
///
/// 실제 차량에서 표준 OBD-II PID(RPM·속도·스로틀·엔진부하)만 저주기로 읽는다.
///
/// ── 허용 명령 (hardcoded) ────────────────────────────────────────
///   010C RPM  · 010D 속도  · 0111 스로틀  · 0104 엔진부하
///
/// ── 금지 사항 ────────────────────────────────────────────────────
///   조향각 · 방향지시등 · Raw CAN · 제조사 PID (22xx) · UDS
///   DTC 삭제(04) · ECU 리셋(11) · 제어 명령
///
/// ── 안전 장치 ────────────────────────────────────────────────────
///   1. 모든 명령은 [SafeObdCommandValidator.assertSafe] 이중 통과 후 전송
///   2. 허용 목록 외 명령 감지 시 즉시 스트림 종료
///   3. 연속 [maxConsecutiveErrors]회 에러 사이클 → 자동 중단
///   4. 모든 전송 명령/응답을 [commandLog]에 기록
class RealReadOnlyDataSource implements DrivingDataSource {
  final ObdDatasource _obd;

  /// PID 간 최소 대기 시간 (기본 500ms)
  ///
  /// 차량 안전을 위해 ELM327에 너무 빠르게 명령을 보내지 않는다.
  /// 발표 주행 테스트 권장값: 500ms (→ 샘플 주기 ≈ 2~3초)
  final Duration interPidDelay;

  // ── 로그 및 통계 ────────────────────────────────────────────────────────────
  final List<ObdDriveLog> commandLog = [];

  int _totalSamples    = 0;
  int _totalErrors     = 0;
  int _blockedAttempts = 0;

  int get totalSamples    => _totalSamples;
  int get totalErrors     => _totalErrors;
  int get blockedAttempts => _blockedAttempts;

  // ── 자동 중단 ───────────────────────────────────────────────────────────────
  int _consecutiveErrorCycles = 0;

  /// 연속 에러 사이클 허용 횟수 — 초과 시 자동 중단
  static const int maxConsecutiveErrors = 3;

  bool    _stopped    = false;
  String? _stopReason;

  bool    get isStopped  => _stopped;
  String? get stopReason => _stopReason;

  // ── 주행 전용 PID 목록 ────────────────────────────────────────────────────
  /// 실차 주행 중 반복 요청하는 PID — SafeObdCommandValidator 허용 목록 내에서만
  ///
  /// 절대 추가하면 안 되는 것:
  ///   조향각(제조사 PID) · 깜빡이 · ABS/ESC · 브레이크 · 변속
  ///   DTC 삭제(04) · ECU 리셋(11) · UDS(10xx) · 제조사 전용 PID(22xx)
  static const _drivingPids = <String>['010C', '010D', '0111', '0104'];

  RealReadOnlyDataSource({
    required ObdDatasource obd,
    this.interPidDelay = const Duration(milliseconds: 500),
  }) : _obd = obd;

  // ── 단일 PID 수동 테스트 (안전 게이트 Step 2용) ────────────────────────────
  ///
  /// [pid]를 SafeObdCommandValidator로 검증한 후 OBD에 전송하고 결과를 반환한다.
  /// 허용 목록에 없는 PID는 차단하고 [ObdDriveLog.blocked]를 반환한다.
  Future<ObdDriveLog> testSinglePid(String pid) async {
    final cmd = pid.trim().toUpperCase().replaceAll('\r', '');

    if (!SafeObdCommandValidator.isAllowed(cmd)) {
      _blockedAttempts++;
      developer.log('[REAL-DRIVE] BLOCKED manual test: $cmd',
          name: 'RealReadOnly', level: 900);
      final log = ObdDriveLog.blocked(cmd);
      commandLog.add(log);
      return log;
    }

    developer.log('[REAL-DRIVE] testSinglePid: $cmd', name: 'RealReadOnly');
    try {
      // sendCommand 내부에서도 SafeObdCommandValidator.assertSafe 호출 (이중 검증)
      final response = await _obd.sendCommand(cmd);
      final err      = _detectError(response);
      final parsed   = _parsePid(cmd, response);
      final log      = ObdDriveLog.fromResponse(
        command:  cmd,
        response: response,
        parsed:   parsed,
        error:    err,
      );
      commandLog.add(log);
      if (err != null) _totalErrors++;
      return log;
    } on UnsafeObdCommandException {
      _blockedAttempts++;
      final log = ObdDriveLog.blocked(cmd);
      commandLog.add(log);
      return log;
    } catch (e) {
      _totalErrors++;
      final log = ObdDriveLog.error(cmd, e.toString());
      commandLog.add(log);
      return log;
    }
  }

  // ── 정차 저주기 폴링 테스트 (안전 게이트 Step 3용) ─────────────────────────
  ///
  /// P단 정차 상태에서 [sampleCount]회 × [sampleInterval] 간격으로 폴링한다.
  /// 에러 사이클이 하나도 없어야 통과.
  Future<StationaryTestResult> runStationaryTest({
    int      sampleCount    = 5,
    Duration sampleInterval = const Duration(seconds: 2),
    void Function(int done, int total)? onProgress,
  }) async {
    final testLogs   = <ObdDriveLog>[];
    int   errorCount = 0;

    developer.log(
      '[REAL-DRIVE] 정차 테스트 시작 — ${sampleCount}회, 간격 ${sampleInterval.inMilliseconds}ms',
      name: 'RealReadOnly',
    );

    for (int i = 0; i < sampleCount; i++) {
      if (_stopped) break;
      bool cycleError = false;

      for (final pid in _drivingPids) {
        // 허용 목록 재확인 (이중 안전)
        if (!SafeObdCommandValidator.isAllowed(pid)) {
          return StationaryTestResult(
            passed: false,
            logs:   testLogs,
            error:  '허용 목록 외 PID 감지: $pid — 즉시 중단',
          );
        }

        try {
          final response = await _obd.sendCommand(pid);
          final err      = _detectError(response);
          final log      = ObdDriveLog.fromResponse(
            command:  pid,
            response: response,
            parsed:   _parsePid(pid, response),
            error:    err,
          );
          testLogs.add(log);
          commandLog.add(log);
          if (err != null) { cycleError = true; _totalErrors++; }
        } on UnsafeObdCommandException {
          _blockedAttempts++;
          final log = ObdDriveLog.blocked(pid);
          testLogs.add(log);
          commandLog.add(log);
          cycleError = true;
        } catch (e) {
          final log = ObdDriveLog.error(pid, e.toString());
          testLogs.add(log);
          commandLog.add(log);
          cycleError = true;
          _totalErrors++;
        }

        await Future.delayed(interPidDelay);
      }

      if (cycleError) errorCount++;
      onProgress?.call(i + 1, sampleCount);

      // 남은 사이클 대기 (PID 폴링에 쓴 시간 제외)
      if (i < sampleCount - 1) {
        final pidTime   = interPidDelay * _drivingPids.length;
        final remaining = sampleInterval - pidTime;
        if (remaining > Duration.zero) await Future.delayed(remaining);
      }
    }

    developer.log(
      '[REAL-DRIVE] 정차 테스트 완료 — 에러 $errorCount/${sampleCount}',
      name: 'RealReadOnly',
    );

    return StationaryTestResult(
      passed: errorCount == 0,
      logs:   testLogs,
      error:  errorCount > 0 ? '${errorCount}개 사이클에서 에러 발생' : null,
    );
  }

  // ── 주행 스트림 (DrivingDataSource 구현) ─────────────────────────────────
  ///
  /// [vin]은 샘플 식별용 — 주행 중 OBD로 재요청하지 않는다.
  /// 스트림은 자동 중단 또는 [dispose] 호출 시 종료된다.
  @override
  Stream<DrivingSample> watchDrivingData(String vin) async* {
    developer.log(
      '[REAL-DRIVE] 주행 스트림 시작 — interPidDelay: ${interPidDelay.inMilliseconds}ms',
      name: 'RealReadOnly',
    );

    while (!_stopped) {
      final cycleStart    = DateTime.now();
      bool  cycleHasError = false;

      double rpm = 0, speed = 0, throttle = 0, engineLoad = 0;

      for (final pid in _drivingPids) {
        if (_stopped) break;

        // ── 이중 안전 검증 ─────────────────────────────────────────────────
        if (!SafeObdCommandValidator.isAllowed(pid)) {
          _stopped    = true;
          _stopReason = 'SafeObdCommandValidator 차단: $pid — 허용 목록 외 명령 감지';
          developer.log('[REAL-DRIVE] CRITICAL: pid $pid not in allowlist!',
              name: 'RealReadOnly', level: 1000);
          return; // 즉시 스트림 종료
        }

        try {
          final response = await _obd.sendCommand(pid);
          final err      = _detectError(response);
          final parsed   = _parsePid(pid, response);

          commandLog.add(ObdDriveLog.fromResponse(
            command:  pid,
            response: response,
            parsed:   parsed,
            error:    err,
          ));

          if (err != null) {
            cycleHasError = true;
            _totalErrors++;
            developer.log('[REAL-DRIVE] pid error $pid: $err', name: 'RealReadOnly');
          } else {
            final val = _parseDouble(pid, response);
            if (val != null) {
              switch (pid) {
                case '010C': rpm        = val; break;
                case '010D': speed      = val; break;
                case '0111': throttle   = val; break;
                case '0104': engineLoad = val; break;
              }
            }
          }
        } on UnsafeObdCommandException {
          // sendCommand 내부 validator 차단 → 즉시 중단
          _stopped         = true;
          _stopReason      = 'SafeObdCommandValidator 차단: $pid';
          _blockedAttempts++;
          developer.log('[REAL-DRIVE] BLOCKED in stream: $pid',
              name: 'RealReadOnly', level: 1000);
          commandLog.add(ObdDriveLog.blocked(pid));
          return;
        } catch (e) {
          cycleHasError = true;
          _totalErrors++;
          commandLog.add(ObdDriveLog.error(pid, e.toString()));
          developer.log('[REAL-DRIVE] exception $pid: $e', name: 'RealReadOnly');
        }

        if (!_stopped) await Future.delayed(interPidDelay);
      }

      if (_stopped) break;

      // ── 연속 에러 사이클 추적 ─────────────────────────────────────────────
      if (cycleHasError) {
        _consecutiveErrorCycles++;
        if (_consecutiveErrorCycles >= maxConsecutiveErrors) {
          _stopped    = true;
          _stopReason = 'OBD 통신 안정성 문제로 데이터 수집을 중단했습니다. 차량 상태를 확인하세요.';
          developer.log(
            '[REAL-DRIVE] auto-stop: $maxConsecutiveErrors consecutive error cycles',
            name:  'RealReadOnly',
            level: 900,
          );
          break;
        }
      } else {
        _consecutiveErrorCycles = 0;
      }

      _totalSamples++;
      yield DrivingSample(
        timestamp:  cycleStart,
        speed:      speed.clamp(0, 300),
        rpm:        rpm.clamp(0, 8000),
        throttle:   throttle.clamp(0, 100),
        engineLoad: engineLoad.clamp(0, 100),
        vin:        vin,
      );
    }

    developer.log(
      '[REAL-DRIVE] 스트림 종료 — samples: $_totalSamples, '
      'errors: $_totalErrors, reason: $_stopReason',
      name: 'RealReadOnly',
    );
  }

  @override
  void dispose() {
    if (!_stopped) {
      _stopped    = true;
      _stopReason = '사용자가 중단';
    }
    developer.log('[REAL-DRIVE] disposed', name: 'RealReadOnly');
  }

  // ── 내부 헬퍼 ─────────────────────────────────────────────────────────────

  String? _parsePid(String pid, String response) {
    switch (pid) {
      case '010C':
        final v = ObdPidParser.parseRpm(response);
        return v != null ? 'rpm: ${v.toStringAsFixed(0)}' : null;
      case '010D':
        final v = ObdPidParser.parseSpeed(response);
        return v != null ? 'speed: ${v.toStringAsFixed(0)} km/h' : null;
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

  double? _parseDouble(String pid, String response) {
    switch (pid) {
      case '010C': return ObdPidParser.parseRpm(response);
      case '010D': return ObdPidParser.parseSpeed(response);
      case '0111': return ObdPidParser.parseThrottle(response);
      case '0104': return ObdPidParser.parseEngineLoad(response);
      default:     return null;
    }
  }

  /// ELM327 오류 응답 감지
  String? _detectError(String response) {
    final upper = response.toUpperCase();
    if (upper.contains('NO DATA'))           return 'NO DATA';
    if (upper.contains('UNABLE TO CONNECT')) return 'UNABLE TO CONNECT';
    if (upper.contains('BUS ERROR'))         return 'BUS ERROR';
    if (upper.contains('CAN ERROR'))         return 'CAN ERROR';
    if (upper.contains('STOPPED'))           return 'STOPPED';
    if (upper.contains('ERR'))               return 'ERROR';
    if (response.trim().isEmpty)             return '응답 없음';
    return null;
  }
}
