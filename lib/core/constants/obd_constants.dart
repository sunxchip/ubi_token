class ObdConstants {
  // ── AT 초기화 명령어 ───────────────────────────────────
  static const String cmdReset          = 'ATZ\r';
  static const String cmdEchoOff        = 'ATE0\r';
  static const String cmdHeaderOn       = 'ATH1\r';
  static const String cmdLineFeedOff    = 'ATL0\r';
  static const String cmdAdaptiveTiming = 'ATAT1\r';
  static const String cmdProtocol6      = 'ATSP6\r';

  // ── 표준 OBD-II PID ───────────────────────────────────
  static const String pidSpeed           = '010D\r'; // 차량 속도 km/h
  static const String pidRpm             = '010C\r'; // 엔진 RPM
  static const String pidVin             = '0902\r'; // 차대번호 (모드 09 PID 02)
  static const String pidThrottlePosition = '0111\r'; // 스로틀 위치 0~100%
  static const String pidEngineLoad      = '0104\r'; // 엔진 부하 0~100%

  // ── 아반떼 AD 전용 CAN ID (실차 검증 결과) ────────────
  static const String canIdSteering = '2B0'; // 조향각 센서 (검증 완료)
  static const String canIdBcm      = '386'; // BCM 방향지시등 (검증 완료)

  // 0x386 프레임 구조 (아반떼 AD 2016 실차 검증)
  // 386 [B0] [B1] [B2] [B3] [B4] [B5] [B6] [B7]
  // 우회전 flash: B1 0x40→0xC0, B3 0x00→0x80 (bit7 토글)
  // 좌회전: ⚠ 미검증 - 실차 테스트 필요
  static const int turnSignalByteIndex = 1;   // byte1 (parts[2]) 기준
  static const int turnRightMask       = 0x80; // byte1 bit7 = 우회전 (검증 완료)
  static const int turnLeftMask        = 0x00; // ⚠ 미검증 (좌회전 테스트 후 업데이트)

  // ── 기존 점수 임계값 (대시보드/조향각 기반) ───────────
  static const double suddenAccelRpmDelta = 1000.0; // 급가속 RPM 변화량
  static const double suddenBrakeKphDelta = 15.0;   // 급감속 속도 변화량 km/h
  static const double steeringThreshold   = 200.0;  // 급조향 임계값 도/초
  static const int    engineOffDelayMs    = 30000;  // 시동 OFF 판정 딜레이 30초

  // ── 안전점수 엔진용 임계값 ────────────────────────────
  // 급가속/급감속은 별도 OBD PID 없이 차량 속도(010D) 변화량으로 계산
  // acceleration = ((currentSpeed - prevSpeed) / 3.6) / deltaTimeSec  (단위: m/s²)
  static const double harshAccelThreshold     = 2.5;  // 급가속 판정 m/s²
  static const double harshBrakeThreshold     = -3.0; // 급감속 판정 m/s² (음수)
  static const double highRpmThreshold        = 3500.0; // 고RPM 판정 기준
  static const double idleSpeedThreshold      = 3.0;   // 공회전 판정 속도 km/h
  static const double idleRpmThreshold        = 700.0;  // 공회전 판정 RPM
  static const double throttleSpikeThreshold  = 30.0;  // 스로틀 급변 판정 %
  static const double engineLoadThreshold     = 80.0;  // 엔진 과부하 판정 %
  static const double hardStartRpmThreshold   = 3000.0; // 급출발 RPM 기준

  // 지속 이벤트 판정 시간 (초)
  static const int highRpmDurationSec       = 3;  // 고RPM 지속 판정 초
  static const int idlingDurationSec        = 60; // 공회전 지속 판정 초
  static const int engineOverloadDurationSec = 5; // 엔진 과부하 지속 판정 초

  // 이벤트 쿨타임 (초) - 중복 감점 방지
  static const int eventCooldownSec = 5;

  // ── 감점 기준 ─────────────────────────────────────────
  static const int penaltyHarshAccel    = 3;
  static const int penaltyHarshBrake    = 4;
  static const int penaltyHardStart     = 4;
  static const int penaltyHighRpm       = 2;
  static const int penaltyThrottleSpike = 2;
  static const int penaltyIdling        = 2;
  static const int penaltyEngineOverload = 2;
  // TODO: 과속 감점 기준 (ITS API 연동 후 추가 예정)
  // static const int penaltySpeeding = 3; // 3~5점 범위로 확정 예정
}
