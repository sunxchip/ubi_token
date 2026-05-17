enum EventType {
  // ── 기존 이벤트 (대시보드/RPM·조향각 기반) ─────────────
  suddenAccel,    // 급가속 (RPM 변화량 기반, 기존 대시보드용)
  suddenBrake,    // 급감속 (속도 변화량 기반, 기존 대시보드용)
  suddenSteering, // 급조향
  speeding,       // 과속 (TODO: ITS API 연동 후 활성화)
  hazardLight,    // 비상등 (방어운전 가산)

  // ── 안전점수 엔진용 이벤트 (가속도 m/s² 기반) ─────────
  harshAccel,     // 급가속 (가속도 >= 2.5 m/s²)
  harshBrake,     // 급감속 (가속도 <= -3.0 m/s²)
  hardStart,      // 급출발 (저속+스로틀급변+고RPM 복합)
  highRpm,        // 고RPM 지속 (3500rpm 이상 3초+)
  throttleSpike,  // 스로틀 급변 (변화량 30% 이상)
  idling,         // 장시간 공회전 (60초 이상)
  engineOverload, // 엔진 과부하 (부하율 80% 이상 5초+)
}

class DriveEvent {
  final EventType type;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double value;   // 발생 시점의 측정값
  final String title;   // 이벤트 한글 제목
  final String description; // 이벤트 상세 설명
  final int penalty;    // 감점 점수 (0 = 가산 이벤트)

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