import 'dart:developer' as developer;

class UnsafeObdCommandException implements Exception {
  final String command;
  const UnsafeObdCommandException(this.command);

  @override
  String toString() => 'BLOCKED unsafe OBD command: $command';
}

/// 표준 OBD-II 읽기 전용 명령 검증기
///
/// 실제 차량에 전송 가능한 명령을 허용 목록으로만 제한한다.
/// 제조사 전용 PID, CAN 헤더 설정, 제어/삭제/초기화 명령은 모두 차단한다.
///
/// 안전 원칙:
///   - 허용 목록에 없는 명령은 기본적으로 차단
///   - 공백 제거 및 대문자 변환 후 비교
///   - 긴 hex 문자열(Raw CAN)은 길이로 추가 차단
class SafeObdCommandValidator {
  static const _allowedCommands = {
    // ── AT 초기화 명령 (ELM327 제어 전용) ─────────────────
    'ATZ',    // ELM327 리셋
    'ATE0',   // 에코 OFF
    'ATL0',   // 줄바꿈 OFF
    'ATS0',   // 공백 OFF
    'ATH0',   // 헤더 OFF
    'ATSP0',  // 프로토콜 자동 선택

    // ── 표준 OBD-II 서비스 01 PID (읽기 전용) ────────────
    '0100',   // 지원 PID 확인
    '0104',   // 엔진 부하 (Calculated Engine Load)
    '0105',   // 냉각수 온도 (Coolant Temperature)
    '010C',   // 엔진 RPM
    '010D',   // 차량 속도 (Vehicle Speed)
    '0111',   // 스로틀 위치 (Throttle Position)
    '012F',   // 연료 레벨 (Fuel Level)

    // ── 표준 OBD-II 서비스 09 (차량 정보, 읽기 전용) ──────
    '0902',   // VIN 조회

    // ── 표준 OBD-II 서비스 03 (DTC 읽기 전용) ────────────
    '03',     // DTC 읽기 (읽기만 허용, 삭제 명령 04는 차단)
  };

  /// 명령이 허용 목록에 있으면 true를 반환한다.
  ///
  /// 공백과 캐리지리턴을 제거하고 대문자 변환 후 비교한다.
  static bool isAllowed(String command) {
    final normalized = command
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    return _allowedCommands.contains(normalized);
  }

  /// 명령이 차단되면 로그를 남기고 [UnsafeObdCommandException]을 던진다.
  static void assertSafe(String command) {
    if (!isAllowed(command)) {
      final msg = 'BLOCKED unsafe OBD command: $command';
      developer.log(msg, name: 'SafeObdCommandValidator', level: 900);
      throw UnsafeObdCommandException(command);
    }
  }
}
