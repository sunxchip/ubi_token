class ObdConstants {
  // ── AT 초기화 명령어 ───────────────────────────────────
  static const String cmdReset          = 'ATZ\r';
  static const String cmdEchoOff        = 'ATE0\r';
  static const String cmdHeaderOn       = 'ATH1\r';
  static const String cmdLineFeedOff    = 'ATL0\r';
  static const String cmdAdaptiveTiming = 'ATAT1\r';
  static const String cmdProtocol6      = 'ATSP6\r';

  // ── 표준 OBD-II PID ───────────────────────────────────
  static const String pidSpeed = '010D\r'; // 차량 속도 km/h
  static const String pidRpm   = '010C\r'; // 엔진 RPM
  static const String pidVin   = '0902\r'; // 차대번호 (모드 09 PID 02)

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

  // ── 점수 임계값 ───────────────────────────────────────
  static const double suddenAccelRpmDelta = 1000.0; // 급가속 RPM 변화량
  static const double suddenBrakeKphDelta = 15.0;   // 급감속 속도 변화량 km/h
  static const double steeringThreshold   = 200.0;  // 급조향 임계값 도/초 (실차 데이터: 일반회전 100~180°/s, 급조향 200°/s+)
  static const int    engineOffDelayMs    = 30000;  // 시동 OFF 판정 딜레이 30초
}
