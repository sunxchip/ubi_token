enum EventType {
  suddenAccel,    // 급가속
  suddenBrake,    // 급감속
  suddenSteering, // 급조향
  speeding,       // 과속
  hazardLight,    // 비상등 (방어운전 가산)
}

class DriveEvent {
  final EventType type;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double value; // 발생 시점의 측정값

  const DriveEvent({
    required this.type,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.value,
  });

  Map<String, dynamic> toMap() => {
    'type'      : type.index,
    'timestamp' : timestamp.millisecondsSinceEpoch,
    'latitude'  : latitude,
    'longitude' : longitude,
    'value'     : value,
  };
}