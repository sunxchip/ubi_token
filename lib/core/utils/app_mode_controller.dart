import '../enums/obd_connection_mode.dart';

/// 앱 전체 OBD 연결 모드 관리 싱글턴
///
/// 기본값은 [ObdConnectionMode.mock].
/// 절대로 real이 기본값이 되어서는 안 된다.
///
/// Real 모드는 [canActivateReal]이 true일 때만 전환 가능하다.
class AppModeController {
  static final AppModeController _instance = AppModeController._();
  factory AppModeController() => _instance;
  AppModeController._();

  ObdConnectionMode _mode = ObdConnectionMode.mock;
  ObdConnectionMode get mode => _mode;

  void setMode(ObdConnectionMode mode) => _mode = mode;

  // ── Real 모드 언락 조건 ──────────────────────────────────────────────────
  /// Dry-run 허용 명령 테스트 통과 여부
  bool dryRunTestPassed = false;

  /// 위험 명령 차단 테스트 통과 여부 (10개 모두 차단)
  bool blockTestPassed = false;

  /// 경고 문구 확인 완료 여부
  bool warningConfirmed = false;

  /// SafeObdCommandValidator는 항상 존재하므로 별도 체크 불필요
  /// 나머지 3가지 조건이 모두 충족되어야 Real 모드 활성화 가능
  bool get canActivateReal =>
      dryRunTestPassed && blockTestPassed && warningConfirmed;

  /// 앱 재시작이나 연결 해제 시 상태 초기화
  void reset() {
    _mode = ObdConnectionMode.mock;
    dryRunTestPassed = false;
    blockTestPassed  = false;
    warningConfirmed = false;
  }
}
