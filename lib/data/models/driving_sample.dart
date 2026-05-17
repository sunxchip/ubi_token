/// OBD-II에서 1초마다 수집하는 주행 데이터 스냅샷
///
/// 실제 연결 시 사용하는 PID:
///   속도:      010D (차량 속도 km/h)
///   RPM:       010C (엔진 RPM)
///   스로틀:    0111 (스로틀 위치 0~100%)
///   엔진 부하: 0104 (엔진 부하 0~100%)
///   VIN:       0902 (차대번호, 인증 시에만 사용)
class DrivingSample {
  final DateTime timestamp;
  final double speed;       // 차량 속도 (km/h)
  final double rpm;         // 엔진 RPM
  final double throttle;    // 스로틀 위치 (0~100%)
  final double engineLoad;  // 엔진 부하율 (0~100%)
  final String vin;         // 차대번호 (인증된 VIN)

  const DrivingSample({
    required this.timestamp,
    required this.speed,
    required this.rpm,
    required this.throttle,
    required this.engineLoad,
    required this.vin,
  });
}
