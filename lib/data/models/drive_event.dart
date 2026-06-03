enum EventType {
  // ── 기존 대시보드용 이벤트 (속도·RPM 변화량 기반) ─────
  suddenAccel, // 급가속 (RPM 변화량 기반)
  suddenBrake, // 급감속 (속도 변화량 기반)
  speeding,    // 과속 (TODO: ITS API 연동 후 활성화)

  // ── 안전점수 엔진용 이벤트 (가속도 m/s² 기반) ─────────
  harshAccel,     // 급가속 (가속도 >= 2.5 m/s²)
  harshBrake,     // 급감속 (가속도 <= -3.0 m/s²)
  hardStart,      // 급출발 (저속+스로틀급변+고RPM 복합)
  highRpm,        // 고RPM 지속 (3500rpm 이상 3초+)
  throttleSpike,  // 스로틀 급변 (변화량 30% 이상)
  idling,         // 장시간 공회전 (60초 이상)
  engineOverload, // 엔진 과부하 (부하율 80% 이상 5초+)
}

// 참고: 조향각 및 방향지시등 이벤트(suddenSteering, hazardLight)는
// 제조사 고유 CAN 신호 해석이 필요하고 안전성 검증이 필요하므로
// 본 구현 범위에서 제외하였다.

class DriveEvent {
  final EventType type;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double value;
  final String title;
  final String description;
  final int penalty;

  const DriveEvent({
    required this.type,
    required this.timestamp,
    this.latitude    = 0.0,
    this.longitude   = 0.0,
    this.value       = 0.0,
    this.title       = '',
    this.description = '',
    this.penalty     = 0,
  });

  Map<String, dynamic> toMap() => {
    'type'        : type.index,
    'timestamp'   : timestamp.millisecondsSinceEpoch,
    'latitude'    : latitude,
    'longitude'   : longitude,
    'value'       : value,
    'title'       : title,
    'description' : description,
    'penalty'     : penalty,
  };
}
