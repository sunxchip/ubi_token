/// OBD 연결 모드
///
/// mock:   실제 스캐너 없음 · MockObdDataSource 사용 · 안전점수 UI 테스트
/// dryRun: 스캐너/차량에 명령 전송 없음 · 샘플 응답으로 파서·UI 검증
/// real:   실제 ELM327 BLE 연결 · SafeObdCommandValidator 허용 명령만 전송
///
/// 기본값은 반드시 mock 또는 dryRun이어야 한다.
/// real은 모든 안전 검증 조건을 충족한 후 명시적으로만 활성화된다.
enum ObdConnectionMode {
  mock,
  dryRun,
  real,
}

extension ObdConnectionModeExt on ObdConnectionMode {
  String get label {
    switch (this) {
      case ObdConnectionMode.mock:   return 'Mock';
      case ObdConnectionMode.dryRun: return 'Dry-run';
      case ObdConnectionMode.real:   return 'Real OBD';
    }
  }

  String get badge {
    switch (this) {
      case ObdConnectionMode.mock:   return '모의 데이터';
      case ObdConnectionMode.dryRun: return '명령 전송 없음';
      case ObdConnectionMode.real:   return '실제 OBD 연결';
    }
  }

  String get description {
    switch (this) {
      case ObdConnectionMode.mock:
        return '실제 스캐너 없음 · MockObdDataSource 사용 · 안전점수 UI 테스트';
      case ObdConnectionMode.dryRun:
        return '실제 차량에 명령 전송 없음 · 샘플 응답으로 파서·UI 검증 · 실차 연결 전 안전 확인용';
      case ObdConnectionMode.real:
        return '실제 ELM327 BLE 연결 · SafeObdCommandValidator 허용 명령만 전송 · 표준 OBD-II 읽기 전용';
    }
  }

  /// 실제 차량에 명령이 전송되는 모드인지 여부
  bool get sendsToVehicle => this == ObdConnectionMode.real;
}
