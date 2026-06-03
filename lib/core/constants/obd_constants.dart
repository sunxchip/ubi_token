class ObdConstants {
  // ── AT 초기화 명령어 (표준, 읽기 전용) ───────────────────
  static const String cmdReset       = 'ATZ\r';   // ELM327 리셋
  static const String cmdEchoOff     = 'ATE0\r';  // 에코 OFF
  static const String cmdLineFeedOff = 'ATL0\r';  // 줄바꿈 OFF
  static const String cmdSpacesOff   = 'ATS0\r';  // 공백 OFF
  static const String cmdHeaderOff   = 'ATH0\r';  // 헤더 OFF (Raw CAN 접근 불가)
  static const String cmdProtocolAuto = 'ATSP0\r'; // 프로토콜 자동 선택

  // ── 표준 OBD-II PID (읽기 전용) ──────────────────────────
  static const String pidSupportedPids     = '0100\r'; // 지원 PID 확인
  static const String pidEngineLoad        = '0104\r'; // 엔진 부하 0~100%
  static const String pidCoolantTemp       = '0105\r'; // 냉각수 온도
  static const String pidRpm              = '010C\r'; // 엔진 RPM
  static const String pidSpeed            = '010D\r'; // 차량 속도 km/h
  static const String pidThrottlePosition = '0111\r'; // 스로틀 위치 0~100%
  static const String pidFuelLevel        = '012F\r'; // 연료 레벨 (선택)
  static const String pidVin              = '0902\r'; // 차대번호 (모드 09 PID 02)
  static const String pidDtcRead         = '03\r';   // DTC 읽기 (읽기만 허용)

  // ── 안전점수 엔진용 임계값 ────────────────────────────────
  // 조향각, 방향지시등, 브레이크, 휠스피드 관련 임계값은 제거됨
  // (제조사 고유 CAN 신호 해석이 필요하고 안전성 검증이 필요하므로 제외)
  static const double harshAccelThreshold     = 2.5;   // 급가속 판정 m/s²
  static const double harshBrakeThreshold     = -3.0;  // 급감속 판정 m/s² (음수)
  static const double highRpmThreshold        = 3500.0; // 고RPM 판정 기준
  static const double idleSpeedThreshold      = 3.0;   // 공회전 판정 속도 km/h
  static const double idleRpmThreshold        = 700.0;  // 공회전 판정 RPM
  static const double throttleSpikeThreshold  = 30.0;  // 스로틀 급변 판정 %
  static const double engineLoadThreshold     = 80.0;  // 엔진 과부하 판정 %
  static const double hardStartRpmThreshold   = 3000.0; // 급출발 RPM 기준

  // 기존 대시보드 급가속/급감속 판정 (속도/RPM 변화량 기반)
  static const double suddenAccelRpmDelta = 1000.0; // 급가속 RPM 변화량
  static const double suddenBrakeKphDelta = 15.0;   // 급감속 속도 변화량 km/h

  // 지속 이벤트 판정 시간 (초)
  static const int highRpmDurationSec        = 3;  // 고RPM 지속 판정 초
  static const int idlingDurationSec         = 60; // 공회전 지속 판정 초
  static const int engineOverloadDurationSec = 5;  // 엔진 과부하 지속 판정 초

  // 이벤트 쿨타임 (초) - 중복 감점 방지
  static const int eventCooldownSec = 5;

  // 기타
  static const int engineOffDelayMs = 30000; // 시동 OFF 판정 딜레이 30초

  // ── 감점 기준 ─────────────────────────────────────────────
  static const int penaltyHarshAccel    = 3;
  static const int penaltyHarshBrake    = 4;
  static const int penaltyHardStart     = 4;
  static const int penaltyHighRpm       = 2;
  static const int penaltyThrottleSpike = 3; // 스로틀 중심 가중치 반영 (2→3)
  static const int penaltyIdling        = 2;
  static const int penaltyEngineOverload = 2;
}
