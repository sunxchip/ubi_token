/// OBD 연결 모드
///
/// mock:               실제 스캐너 없음 · MockObdDataSource · 안전점수 UI 테스트
/// dryRun:             명령 전송 없음 · 샘플 응답으로 파서/UI 검증
/// realReadOnlyDrive:  실차 표준 PID 읽기 전용 주행 기록 모드 (안전 게이트 통과 후 활성화)
/// real:               추후 확장 예정 실차 전체 모드
///
/// 기본값은 반드시 mock 또는 dryRun이어야 한다.
/// realReadOnlyDrive와 real은 모든 안전 검증 조건 충족 후에만 활성화된다.
enum ObdConnectionMode {
  mock,
  dryRun,
  realReadOnlyDrive,
  real,
}

extension ObdConnectionModeExt on ObdConnectionMode {
  String get label {
    switch (this) {
      case ObdConnectionMode.mock:               return 'Mock';
      case ObdConnectionMode.dryRun:             return 'Dry-run';
      case ObdConnectionMode.realReadOnlyDrive:  return '실차 읽기 전용';
      case ObdConnectionMode.real:               return 'Real OBD';
    }
  }

  String get badge {
    switch (this) {
      case ObdConnectionMode.mock:               return '모의 데이터';
      case ObdConnectionMode.dryRun:             return '명령 전송 없음';
      case ObdConnectionMode.realReadOnlyDrive:  return '표준 PID 읽기 전용';
      case ObdConnectionMode.real:               return '실제 OBD 연결';
    }
  }

  String get description {
    switch (this) {
      case ObdConnectionMode.mock:
        return '실제 스캐너 없음 · MockObdDataSource 사용 · 안전점수 UI 테스트';
      case ObdConnectionMode.dryRun:
        return '실제 차량에 명령 전송 없음 · 샘플 응답으로 파서·UI 검증 · 실차 연결 전 안전 확인용';
      case ObdConnectionMode.realReadOnlyDrive:
        return '실차 ELM327 연결 · 010C/010D/0111/0104만 저주기 요청 · 4단계 안전 게이트 통과 필수';
      case ObdConnectionMode.real:
        return '실제 ELM327 BLE 연결 · SafeObdCommandValidator 허용 명령만 전송 · 추후 확장 예정';
    }
  }

  /// 실제 차량에 명령이 전송되는 모드인지 여부
  bool get sendsToVehicle =>
      this == ObdConnectionMode.realReadOnlyDrive ||
      this == ObdConnectionMode.real;
}
