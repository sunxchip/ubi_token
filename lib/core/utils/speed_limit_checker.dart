/// 제한속도 초과 판단 유틸
class SpeedLimitChecker {
  SpeedLimitChecker._();

  /// 현재 OBD 차량 속도가 제한속도를 초과하는지 판단
  ///
  /// [vehicleSpeed] OBD-II 010D PID에서 읽은 차량 속도 (km/h)
  /// [limitSpeed]   VSL API에서 읽은 제한속도 (km/h), null이면 판단 불가
  /// [tolerance]    허용 오차 (km/h), 기본 5km/h
  ///
  /// 반환값: 제한속도 정보 없으면 false (미판정 처리)
  static bool isOverSpeed({
    required double vehicleSpeed,
    required double? limitSpeed,
    double tolerance = 5.0,
  }) {
    if (limitSpeed == null) return false;
    return vehicleSpeed > limitSpeed + tolerance;
  }

  /// 초과 속도 반환 (제한속도 대비 얼마나 빠른지)
  /// 제한속도 정보 없거나 초과 아니면 null
  static double? excessSpeed({
    required double vehicleSpeed,
    required double? limitSpeed,
  }) {
    if (limitSpeed == null) return null;
    final excess = vehicleSpeed - limitSpeed;
    return excess > 0 ? excess : null;
  }
}

/// 지속 시간 기반 과속 판단 카운터
///
/// 1초 샘플 기준으로 과속 상태가 일정 시간 이상 지속될 때만 이벤트 후보로 확정한다.
///
/// TODO: DrivingScoreEngine에 통합하여 과속 감점 이벤트 생성
///       - 제한속도 + 5km/h 초과 5초 이상 지속 → DriveEvent(EventType.speeding, penalty: 3)
///       - 제한속도 + 20km/h 초과 5초 이상 지속 → DriveEvent(EventType.speeding, penalty: 5)
///       - 제한속도 정보 없는 구간은 과속 감점 제외
class OverSpeedCounter {
  int _seconds = 0;

  /// 매 샘플마다 호출. [isOver]가 true이면 카운터 증가, false이면 리셋.
  /// [thresholdSec] 초 이상 누적되면 true 반환 (이벤트 후보 확정)
  bool tick({required bool isOver, int thresholdSec = 5}) {
    if (isOver) {
      _seconds++;
      return _seconds >= thresholdSec;
    } else {
      _seconds = 0;
      return false;
    }
  }

  int get seconds => _seconds;

  void reset() => _seconds = 0;
}
