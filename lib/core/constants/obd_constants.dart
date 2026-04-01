class ObdConstants {
  // AT 초기화 명령어
  static const String cmdReset        = 'ATZ\r';
  static const String cmdEchoOff      = 'ATE0\r';
  static const String cmdHeaderOn     = 'ATH1\r';
  static const String cmdLineFeedOff  = 'ATL0\r';
  static const String cmdAdaptiveTiming = 'ATAT1\r';
  static const String cmdProtocol6    = 'ATSP6\r';

  // 표준 OBD-II PID
  static const String pidSpeed        = '010D\r'; // 차량 속도 km/h
  static const String pidRpm          = '010C\r'; // 엔진 RPM
  static const String pidVin          = '0902\r'; // 차대번호

  // 아반떼 AD 전용 PID (실차 확정)
  static const String pidSteering     = 'ATCF 2B0\r'; // 조향각

  // 점수 임계값
  static const double suddenAccelRpmDelta  = 1000.0; // 급가속 RPM 변화량
  static const double suddenBrakeKphDelta  = 15.0;   // 급감속 속도 변화량 km/h
  static const double steeringThreshold    = 15.0;   // 급조향 임계값 도/초
  static const int    engineOffDelayMs     = 30000;  // 시동 OFF 판정 딜레이 30초
}