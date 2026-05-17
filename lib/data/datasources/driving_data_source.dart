import 'dart:async';
import 'dart:math';
import '../models/driving_sample.dart';

// ── 추상 인터페이스 ────────────────────────────────────────────────────────────
/// OBD 주행 데이터 소스 추상 인터페이스
///
/// 실제 ELM327 OBD-II 스캐너 연결 시 [RealObdDataSource]를 구현하여
/// [MockObdDataSource] 대신 주입하면 된다.
///
/// RealObdDataSource 구현 시 참고:
///   - ObdDatasource.getSpeed()    → DrivingSample.speed
///   - ObdDatasource.getRpm()      → DrivingSample.rpm
///   - ObdDatasource 에 getThrottle(), getEngineLoad() 메서드 추가 필요
///     (PID: 0111, 0104 → 1바이트 응답, A/255 * 100 = %)
abstract class DrivingDataSource {
  /// 1초마다 [DrivingSample]을 방출하는 스트림을 반환한다.
  Stream<DrivingSample> watchDrivingData(String vin);

  void dispose();
}

// ── Mock 구현체 ───────────────────────────────────────────────────────────────
/// Mock OBD 데이터 소스
///
/// 실제 OBD-II 스캐너 없이도 주행 시뮬레이션이 가능하도록
/// 아래 시나리오를 순서대로 방출한다:
///
///   0~ 5초: 공회전 (장기 공회전 이벤트 트리거 준비)
///   6초:    급출발 트리거 (저속+스로틀 급변+고RPM)
///   7~13초: 급가속 구간 (가속도 ≈ 3.3 m/s²)
///  14~21초: 정상 주행
///  22~30초: 고RPM + 엔진 과부하 구간 (각 임계치 지속 초 초과)
///  31~33초: 스로틀 급변
///  34~37초: 급감속 (가속도 ≈ -3.9 m/s²)
///  38~97초: 장기 공회전 (60초 초과 → 공회전 이벤트)
///  98초~:   정상 주행 복귀
///
/// TODO: 실제 ELM327 OBD-II 스캐너 연결 시 이 클래스를 RealObdDataSource로 교체
class MockObdDataSource implements DrivingDataSource {
  StreamController<DrivingSample>? _controller;
  Timer? _timer;
  int _tick = 0;
  final _rng = Random();

  // 현재 시뮬레이션 상태값 (이전 샘플 연속성 유지)
  double _speed      = 0;
  double _rpm        = 800;
  double _throttle   = 5;
  double _engineLoad = 20;

  @override
  Stream<DrivingSample> watchDrivingData(String vin) {
    _controller = StreamController<DrivingSample>.broadcast();
    _tick   = 0;
    _speed  = 0; _rpm = 800; _throttle = 5; _engineLoad = 20;

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tick++;
      _updateState();
      if (!(_controller?.isClosed ?? true)) {
        _controller!.add(DrivingSample(
          timestamp:  DateTime.now(),
          speed:      _speed.clamp(0, 200),
          rpm:        _rpm.clamp(0, 8000),
          throttle:   _throttle.clamp(0, 100),
          engineLoad: _engineLoad.clamp(0, 100),
          vin:        vin,
        ));
      }
    });

    return _controller!.stream;
  }

  void _updateState() {
    final r = _rng;

    if (_tick <= 5) {
      // ── 0~5초: 공회전 ─────────────────────────────────
      _speed      = 0;
      _rpm        = 750  + r.nextDouble() * 100;
      _throttle   = 3    + r.nextDouble() * 2;
      _engineLoad = 15   + r.nextDouble() * 5;

    } else if (_tick == 6) {
      // ── 6초: 급출발 ───────────────────────────────────
      // 조건: 이전 속도 ≤ 3km/h, 스로틀 변화 ≥ 30%, RPM ≥ 3000
      _speed      = 2;
      _rpm        = 3300;
      _throttle   = 48;  // 이전 ~5% → 48% (delta = 43)
      _engineLoad = 65;

    } else if (_tick <= 13) {
      // ── 7~13초: 급가속 ─────────────────────────────────
      // 속도 1초에 12km/h 증가 → accel = 12/3.6 ≈ 3.3 m/s² (임계 2.5 초과)
      _speed      = (_speed + 12 + r.nextDouble() * 2).clamp(0, 90);
      _rpm        = 3000 + _speed * 25 + r.nextDouble() * 300;
      _throttle   = 55   + r.nextDouble() * 15;
      _engineLoad = 65   + r.nextDouble() * 10;

    } else if (_tick <= 21) {
      // ── 14~21초: 정상 주행 ─────────────────────────────
      _speed      = 70 + r.nextDouble() * 10;
      _rpm        = 2200 + r.nextDouble() * 400;
      _throttle   = 28   + r.nextDouble() * 8;
      _engineLoad = 38   + r.nextDouble() * 10;

    } else if (_tick <= 30) {
      // ── 22~30초: 고RPM + 엔진 과부하 지속 ─────────────
      // highRpm:       3500rpm 이상 3초 → tick 24에 이벤트 (3초 누적)
      // engineOverload: 80% 이상 5초   → tick 26에 이벤트 (5초 누적)
      _speed      = 110 + r.nextDouble() * 5;
      _rpm        = 4200 + r.nextDouble() * 300;
      _throttle   = 75   + r.nextDouble() * 10;
      _engineLoad = 87   + r.nextDouble() * 5;

    } else if (_tick <= 33) {
      // ── 31~33초: 스로틀 급변 ───────────────────────────
      // 홀짝 틱마다 스로틀을 10% ↔ 55% 교대 (변화량 45 → 임계 30 초과)
      _speed      = 80 + r.nextDouble() * 5;
      _rpm        = 2600 + r.nextDouble() * 200;
      _throttle   = (_tick.isEven) ? 10 : 55;
      _engineLoad = 42 + r.nextDouble() * 10;

    } else if (_tick <= 37) {
      // ── 34~37초: 급감속 ────────────────────────────────
      // 속도 1초에 14km/h 감소 → accel = -14/3.6 ≈ -3.9 m/s² (임계 -3.0 초과)
      _speed      = (_speed - 14 - r.nextDouble() * 2).clamp(0, 200);
      _rpm        = (900 + _speed * 20 + r.nextDouble() * 150).clamp(0, 8000);
      _throttle   = 4 + r.nextDouble() * 4;
      _engineLoad = 18 + r.nextDouble() * 8;

    } else if (_tick <= 97) {
      // ── 38~97초: 장기 공회전 (60초 초과 → 공회전 이벤트) ─
      _speed      = 0;
      _rpm        = 760 + r.nextDouble() * 100;
      _throttle   = 3   + r.nextDouble() * 2;
      _engineLoad = 14  + r.nextDouble() * 5;

    } else {
      // ── 98초~: 정상 주행 복귀 ──────────────────────────
      _speed      = 55  + r.nextDouble() * 20;
      _rpm        = 1900 + r.nextDouble() * 400;
      _throttle   = 22   + r.nextDouble() * 12;
      _engineLoad = 32   + r.nextDouble() * 15;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.close();
    _timer      = null;
    _controller = null;
  }
}

// TODO: 실제 ELM327 OBD-II 스캐너 연결 시 아래 클래스를 구현하여 교체
// class RealObdDataSource implements DrivingDataSource {
//   final ObdDatasource _obd;
//   const RealObdDataSource(this._obd);
//
//   @override
//   Stream<DrivingSample> watchDrivingData(String vin) async* {
//     while (true) {
//       await Future.delayed(const Duration(seconds: 1));
//       final speed      = await _obd.getSpeed();
//       final rpm        = await _obd.getRpm();
//       final throttle   = await _obd.getThrottle();    // TODO: ObdDatasource에 추가 필요
//       final engineLoad = await _obd.getEngineLoad();  // TODO: ObdDatasource에 추가 필요
//       yield DrivingSample(
//         timestamp: DateTime.now(), speed: speed, rpm: rpm,
//         throttle: throttle, engineLoad: engineLoad, vin: vin,
//       );
//     }
//   }
//
//   @override
//   void dispose() {}
// }
