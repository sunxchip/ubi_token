import 'dart:async';
import 'dart:math';
import '../models/driving_sample.dart';

// ── 시나리오 선택 Enum ────────────────────────────────────────────────────────
/// Mock 주행 시나리오 종류
///
/// 발표/시연 시 원하는 시나리오를 선택하면
/// MockObdDataSource가 해당 패턴의 OBD 데이터를 생성한다.
///
/// TODO: 실제 RealObdDataSource로 전환 시 이 Enum은 UI에서 숨기거나 비활성화
enum MockDriveScenario {
  normal,              // 정상 주행 (점수 높게 유지, 이벤트 거의 없음)
  risky,               // 위험 주행 (급출발·급가속·급감속·고RPM·스로틀급변 혼합)
  idleTest,            // 공회전 이벤트 확인용 (60초 이상 공회전)
  harshAccelBrakeTest, // 급가속/급감속 이벤트 확인용
  highRpmTest,         // 고RPM/엔진과부하 이벤트 확인용
}

extension MockDriveScenarioLabel on MockDriveScenario {
  String get label {
    switch (this) {
      case MockDriveScenario.normal:              return '정상 주행';
      case MockDriveScenario.risky:               return '위험 주행 (종합)';
      case MockDriveScenario.idleTest:            return '공회전 테스트';
      case MockDriveScenario.harshAccelBrakeTest: return '급가속/급감속 테스트';
      case MockDriveScenario.highRpmTest:         return '고RPM 테스트';
    }
  }
}

// ── 추상 인터페이스 ────────────────────────────────────────────────────────────
/// OBD 주행 데이터 소스 추상 인터페이스
///
/// Mock과 Real 모두 동일한 [DrivingSample]을 반환해야 한다.
/// 안전점수 엔진(DrivingScoreEngine)과 UI는 데이터 소스 종류를 알 필요 없다.
abstract class DrivingDataSource {
  /// 1초마다 [DrivingSample]을 방출하는 스트림을 반환한다.
  Stream<DrivingSample> watchDrivingData(String vin);
  void dispose();
}

// ── Mock 구현체 ───────────────────────────────────────────────────────────────
/// Mock OBD 데이터 소스
///
/// [scenario]에 따라 다른 주행 패턴을 생성한다.
/// 기본값은 [MockDriveScenario.risky] (7가지 이벤트 모두 포함).
///
/// TODO: 실제 ELM327 OBD-II 스캐너 연결 시 이 클래스를 [RealObdDataSource]로 교체
class MockObdDataSource implements DrivingDataSource {
  final MockDriveScenario scenario;

  MockObdDataSource({this.scenario = MockDriveScenario.risky});

  StreamController<DrivingSample>? _controller;
  Timer? _timer;
  int _tick = 0;
  final _rng = Random();

  double _speed      = 0;
  double _rpm        = 800;
  double _throttle   = 5;
  double _engineLoad = 20;

  @override
  Stream<DrivingSample> watchDrivingData(String vin) {
    _controller = StreamController<DrivingSample>.broadcast();
    _tick = 0;
    _speed = 0; _rpm = 800; _throttle = 5; _engineLoad = 20;

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
    switch (scenario) {
      case MockDriveScenario.normal:
        _updateNormal();
        break;
      case MockDriveScenario.risky:
        _updateRisky();
        break;
      case MockDriveScenario.idleTest:
        _updateIdleTest();
        break;
      case MockDriveScenario.harshAccelBrakeTest:
        _updateHarshAccelBrakeTest();
        break;
      case MockDriveScenario.highRpmTest:
        _updateHighRpmTest();
        break;
    }
  }

  // ── 시나리오별 업데이트 함수 ─────────────────────────────────────────────

  /// 정상 주행: 부드러운 가속/감속, 이벤트 발생 없음
  void _updateNormal() {
    final r = _rng;
    if (_tick <= 10) {
      // 부드럽게 가속 (가속도 < 2.5 m/s²)
      _speed      = (_speed + 4 + r.nextDouble()).clamp(0, 60);
      _rpm        = 1400 + _speed * 18 + r.nextDouble() * 200;
      _throttle   = 20   + r.nextDouble() * 8;
      _engineLoad = 28   + r.nextDouble() * 10;
    } else if (_tick <= 60) {
      // 정속 주행 (50~70 km/h)
      _speed      = 55 + r.nextDouble() * 10 + (r.nextBool() ? 2.0 : -2.0);
      _rpm        = 1800 + r.nextDouble() * 300;
      _throttle   = 22   + r.nextDouble() * 6;
      _engineLoad = 30   + r.nextDouble() * 8;
    } else if (_tick <= 70) {
      // 부드럽게 감속
      _speed      = (_speed - 3 - r.nextDouble()).clamp(0, 100);
      _rpm        = (800 + _speed * 20 + r.nextDouble() * 150).clamp(700, 8000);
      _throttle   = 5  + r.nextDouble() * 5;
      _engineLoad = 15 + r.nextDouble() * 8;
    } else {
      // 잠시 정차 후 다시 주행
      final phase = (_tick - 70) % 80;
      if (phase < 10) {
        _speed = 0; _rpm = 750 + r.nextDouble() * 80;
        _throttle = 3; _engineLoad = 14;
      } else if (phase < 50) {
        _speed      = 45 + r.nextDouble() * 15;
        _rpm        = 1700 + r.nextDouble() * 300;
        _throttle   = 20  + r.nextDouble() * 8;
        _engineLoad = 28  + r.nextDouble() * 8;
      } else {
        _speed      = (_speed - 2).clamp(0, 100);
        _rpm        = (800 + _speed * 18).clamp(700, 8000);
        _throttle   = 5; _engineLoad = 15;
      }
    }
  }

  /// 위험 주행: 7가지 이벤트(급출발→급가속→고RPM+엔진과부하→스로틀급변→급감속→공회전) 포함
  ///
  ///  0~ 5초: 공회전 대기
  ///  6초:    급출발 (저속+스로틀급변+고RPM)
  ///  7~13초: 급가속 (가속도 ≈ 3.3 m/s²)
  /// 14~21초: 정상 주행
  /// 22~30초: 고RPM + 엔진 과부하 (각 임계 지속 초 초과)
  /// 31~33초: 스로틀 급변
  /// 34~37초: 급감속 (가속도 ≈ -3.9 m/s²)
  /// 38~97초: 장기 공회전 (60초 초과 → 공회전 이벤트)
  /// 98초~:   정상 주행 복귀
  void _updateRisky() {
    final r = _rng;

    if (_tick <= 5) {
      _speed = 0; _rpm = 750 + r.nextDouble() * 100;
      _throttle = 3 + r.nextDouble() * 2; _engineLoad = 15 + r.nextDouble() * 5;
    } else if (_tick == 6) {
      // 급출발: 이전 속도 ≤ 3, 스로틀 +43%, RPM ≥ 3000
      _speed = 2; _rpm = 3300; _throttle = 48; _engineLoad = 65;
    } else if (_tick <= 13) {
      // 급가속: 12km/h/s → accel ≈ 3.3 m/s²
      _speed      = (_speed + 12 + r.nextDouble() * 2).clamp(0, 90);
      _rpm        = 3000 + _speed * 25 + r.nextDouble() * 300;
      _throttle   = 55 + r.nextDouble() * 15; _engineLoad = 65 + r.nextDouble() * 10;
    } else if (_tick <= 21) {
      _speed = 70 + r.nextDouble() * 10; _rpm = 2200 + r.nextDouble() * 400;
      _throttle = 28 + r.nextDouble() * 8; _engineLoad = 38 + r.nextDouble() * 10;
    } else if (_tick <= 30) {
      // 고RPM(3s 후 이벤트) + 엔진과부하(5s 후 이벤트)
      _speed = 110 + r.nextDouble() * 5; _rpm = 4200 + r.nextDouble() * 300;
      _throttle = 75 + r.nextDouble() * 10; _engineLoad = 87 + r.nextDouble() * 5;
    } else if (_tick <= 33) {
      // 스로틀 급변: 홀짝 교대 (변화량 45%)
      _speed = 80 + r.nextDouble() * 5; _rpm = 2600 + r.nextDouble() * 200;
      _throttle = (_tick.isEven) ? 10 : 55; _engineLoad = 42 + r.nextDouble() * 10;
    } else if (_tick <= 37) {
      // 급감속: 14km/h/s → accel ≈ -3.9 m/s²
      _speed      = (_speed - 14 - r.nextDouble() * 2).clamp(0, 200);
      _rpm        = (900 + _speed * 20 + r.nextDouble() * 150).clamp(0, 8000);
      _throttle = 4 + r.nextDouble() * 4; _engineLoad = 18 + r.nextDouble() * 8;
    } else if (_tick <= 97) {
      // 장기 공회전 (60초 초과 → 공회전 이벤트)
      _speed = 0; _rpm = 760 + r.nextDouble() * 100;
      _throttle = 3 + r.nextDouble() * 2; _engineLoad = 14 + r.nextDouble() * 5;
    } else {
      _speed = 55 + r.nextDouble() * 20; _rpm = 1900 + r.nextDouble() * 400;
      _throttle = 22 + r.nextDouble() * 12; _engineLoad = 32 + r.nextDouble() * 15;
    }
  }

  /// 공회전 테스트: 정차 후 60초 이상 공회전 유지
  void _updateIdleTest() {
    final r = _rng;
    if (_tick <= 5) {
      // 처음에 잠깐 달리다가
      _speed = 20 + r.nextDouble() * 5; _rpm = 1400 + r.nextDouble() * 200;
      _throttle = 18 + r.nextDouble() * 5; _engineLoad = 25 + r.nextDouble() * 8;
    } else {
      // 정차 후 공회전 (66초 → 이벤트 발생)
      _speed = 0; _rpm = 750 + r.nextDouble() * 80;
      _throttle = 3 + r.nextDouble() * 1.5; _engineLoad = 14 + r.nextDouble() * 4;
    }
  }

  /// 급가속/급감속 테스트: 10초 단위로 반복
  void _updateHarshAccelBrakeTest() {
    final r = _rng;
    final phase = _tick % 20;

    if (phase < 2) {
      // 저속 대기
      _speed = (_speed - 5).clamp(0, 200); _rpm = (700 + _speed * 20).clamp(700, 8000);
      _throttle = 3; _engineLoad = 15;
    } else if (phase < 7) {
      // 급가속: 13km/h/s → accel ≈ 3.6 m/s²
      _speed      = (_speed + 13 + r.nextDouble() * 2).clamp(0, 100);
      _rpm        = 2800 + _speed * 20 + r.nextDouble() * 300;
      _throttle   = 65 + r.nextDouble() * 15; _engineLoad = 70 + r.nextDouble() * 10;
    } else if (phase < 12) {
      // 정속
      _speed = 65 + r.nextDouble() * 10; _rpm = 2200 + r.nextDouble() * 300;
      _throttle = 28 + r.nextDouble() * 5; _engineLoad = 38 + r.nextDouble() * 8;
    } else {
      // 급감속: 15km/h/s → accel ≈ -4.2 m/s²
      _speed      = (_speed - 15 - r.nextDouble() * 2).clamp(0, 200);
      _rpm        = (700 + _speed * 20).clamp(700, 8000);
      _throttle = 3 + r.nextDouble() * 2; _engineLoad = 18 + r.nextDouble() * 5;
    }
  }

  /// 고RPM/엔진과부하 테스트: 지속적으로 고RPM + 과부하 유지
  void _updateHighRpmTest() {
    final r = _rng;
    if (_tick <= 5) {
      // 준비 구간
      _speed = 40 + r.nextDouble() * 10; _rpm = 1800 + r.nextDouble() * 300;
      _throttle = 22 + r.nextDouble() * 5; _engineLoad = 30 + r.nextDouble() * 8;
    } else {
      // 고RPM + 엔진 과부하 지속 (10초마다 잠깐 낮췄다가 다시 올림)
      final phase = (_tick - 6) % 20;
      if (phase < 14) {
        // 고RPM + 과부하 구간 (14초 → 고RPM 이벤트 4회, 엔진과부하 이벤트 2회)
        _speed = 120 + r.nextDouble() * 10; _rpm = 4500 + r.nextDouble() * 500;
        _throttle = 80 + r.nextDouble() * 10; _engineLoad = 90 + r.nextDouble() * 5;
      } else {
        // 잠깐 정상으로 내려갔다가
        _speed = 80 + r.nextDouble() * 10; _rpm = 2000 + r.nextDouble() * 300;
        _throttle = 28 + r.nextDouble() * 8; _engineLoad = 40 + r.nextDouble() * 10;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.close();
    _timer = null; _controller = null;
  }
}

// ── RealObdDataSource 뼈대 ────────────────────────────────────────────────────
/// 실제 ELM327 OBD-II 스캐너 연결 데이터 소스
///
/// 구현 순서:
///   1. [connect]  → ObdDatasource.connect(device)로 BLE 연결
///   2. [initializeElm327] → AT 명령으로 ELM327 초기화
///   3. [checkSupportedPids] → 0100 응답으로 지원 PID 목록 확인
///   4. [watchDrivingData] → 1초마다 PID 요청 → ObdPidParser로 변환 → DrivingSample 방출
///
/// MockObdDataSource와 동일한 DrivingSample을 반환하므로
/// DrivingScoreScreen은 데이터 소스 교체를 인식하지 않아도 된다.
///
/// TODO: ObdDatasource에 getThrottle(), getEngineLoad() 메서드 추가 필요
///       (PID 0111, 0104 → ObdPidParser.parseThrottle/parseEngineLoad 활용)
class RealObdDataSource implements DrivingDataSource {
  // TODO: ObdDatasource 인스턴스를 생성자에서 주입받거나
  //       ObdDatasource.connected 싱글턴을 사용
  // final ObdDatasource _obd;
  // RealObdDataSource(this._obd);

  StreamController<DrivingSample>? _controller;
  Timer? _timer;
  bool _initialized = false;

  /// ELM327 AT 명령 초기화 (표준 읽기 전용 명령만 사용)
  ///
  /// 초기화 순서 (SafeObdCommandValidator 허용 목록 내 명령만):
  ///   ATZ  → ELM327 리셋
  ///   ATE0 → 에코 OFF
  ///   ATL0 → 줄바꿈 OFF
  ///   ATS0 → 공백 OFF
  ///   ATH0 → 헤더 OFF (Raw CAN 접근 불가)
  ///   ATSP0 → 프로토콜 자동 선택
  ///
  /// 금지: ATAT1(적응형 타이밍), ATSP6(특정 프로토콜 고정),
  ///       ATSH/ATCRA/ATCAF 등 CAN 헤더·필터 관련 명령
  Future<bool> initializeElm327() async {
    // TODO: ObdDatasource.connect() 호출 시 _initialize()에서 자동 처리됨.
    //       별도 초기화 불필요. 아래는 수동 호출 예시만 남김.
    // final commands = [
    //   'ATZ\r',   // 리셋
    //   'ATE0\r',  // 에코 OFF
    //   'ATL0\r',  // 줄바꿈 OFF
    //   'ATS0\r',  // 공백 OFF
    //   'ATH0\r',  // 헤더 OFF
    //   'ATSP0\r', // 프로토콜 자동
    // ];
    // for (final cmd in commands) {
    //   await _obd.sendRaw(cmd);
    //   await Future.delayed(const Duration(milliseconds: 300));
    // }
    _initialized = true;
    return true;
  }

  /// 지원 PID 확인 (서비스01 PID 00 → 비트마스크 응답)
  ///
  /// 응답 예: "41 00 BE 3F A8 13"
  ///   → 비트 분석으로 010C(RPM), 010D(속도), 0111(스로틀), 0104(엔진부하) 지원 여부 확인
  Future<Set<String>> checkSupportedPids() async {
    // TODO: '0100\r' 전송 후 응답 비트마스크 파싱
    // final response = await _obd.sendRaw('0100\r');
    // return _parseSupportedPids(response);

    // 임시 반환: 주요 4개 PID 지원 가정
    return {'010C', '010D', '0111', '0104'};
  }

  /// 단일 PID 요청 및 응답 반환
  ///
  /// [pid] 예시: '010C\r' (RPM)
  Future<String> requestPid(String pid) async {
    // TODO: await _obd.sendRaw(pid) 또는 _obd._requestPid(pid)
    throw UnimplementedError('RealObdDataSource.requestPid() - TODO: ObdDatasource 연결 필요');
  }

  @override
  Stream<DrivingSample> watchDrivingData(String vin) async* {
    // TODO: initializeElm327() 호출 후 아래 루프 실행
    // if (!_initialized) await initializeElm327();

    // TODO: 아래 while 루프 구현
    // while (true) {
    //   await Future.delayed(const Duration(seconds: 1));
    //   try {
    //     final speedRaw  = await requestPid('010D\r');
    //     final rpmRaw    = await requestPid('010C\r');
    //     final throttleRaw   = await requestPid('0111\r');
    //     final engineLoadRaw = await requestPid('0104\r');
    //
    //     final speed      = ObdPidParser.parseSpeed(speedRaw)      ?? 0.0;
    //     final rpm        = ObdPidParser.parseRpm(rpmRaw)          ?? 0.0;
    //     final throttle   = ObdPidParser.parseThrottle(throttleRaw)    ?? 0.0;
    //     final engineLoad = ObdPidParser.parseEngineLoad(engineLoadRaw) ?? 0.0;
    //
    //     yield DrivingSample(
    //       timestamp: DateTime.now(), speed: speed, rpm: rpm,
    //       throttle: throttle, engineLoad: engineLoad, vin: vin,
    //     );
    //   } catch (e) {
    //     // 파싱 실패 시 이전 값 유지하거나 건너뜀
    //     continue;
    //   }
    // }

    throw UnimplementedError('RealObdDataSource.watchDrivingData() - TODO: 실제 OBD 연결 구현 필요');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.close();
    _timer = null; _controller = null;
  }
}
