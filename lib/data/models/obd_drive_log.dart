/// OBD 명령 전송/수신 로그 항목
///
/// 발표 시 "실제로 전송된 명령은 표준 PID 4개뿐"임을 투명하게 증명한다.
/// 주행 종료 후 [RealDriveScreen]의 리포트 화면에서 전체 로그를 표시한다.
class ObdDriveLog {
  final DateTime timestamp;

  /// 전송한 명령 (예: '010C')
  final String command;

  /// SafeObdCommandValidator 통과 여부
  final bool allowed;

  /// ELM327 응답 앞 50자 (줄바꿈/> 제거 후)
  final String responsePreview;

  /// 파싱된 사람이 읽을 수 있는 값 (예: 'rpm: 1250')
  final String? parsedValue;

  /// 에러 메시지 — null이면 정상
  final String? error;

  const ObdDriveLog({
    required this.timestamp,
    required this.command,
    required this.allowed,
    required this.responsePreview,
    this.parsedValue,
    this.error,
  });

  bool get isError   => error != null;
  bool get isBlocked => !allowed;
  bool get isNoData  => responsePreview.toUpperCase().contains('NO DATA');

  // ── 팩토리 생성자 ──────────────────────────────────────────────────────────

  /// SafeObdCommandValidator에 의해 차단된 명령 로그
  factory ObdDriveLog.blocked(String command) => ObdDriveLog(
        timestamp:       DateTime.now(),
        command:         command.trim().toUpperCase(),
        allowed:         false,
        responsePreview: 'BLOCKED',
        error:           'SafeObdCommandValidator 차단',
      );

  /// 예외/타임아웃 등 에러 발생 로그
  factory ObdDriveLog.error(String command, String errorMsg) => ObdDriveLog(
        timestamp:       DateTime.now(),
        command:         command.trim().toUpperCase(),
        allowed:         true,
        responsePreview: 'ERROR',
        error:           errorMsg,
      );

  /// 정상 응답 로그
  factory ObdDriveLog.fromResponse({
    required String command,
    required String response,
    String?         parsed,
    String?         error,
  }) {
    final preview = response
        .replaceAll(RegExp(r'[\r\n>]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return ObdDriveLog(
      timestamp:       DateTime.now(),
      command:         command.trim().toUpperCase(),
      allowed:         true,
      responsePreview: preview.length > 50 ? '${preview.substring(0, 50)}…' : preview,
      parsedValue:     parsed,
      error:           error,
    );
  }
}
