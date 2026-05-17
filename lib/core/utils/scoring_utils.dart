import '../constants/obd_constants.dart';
import '../../data/models/drive_event.dart';
import '../../data/models/driving_sample.dart';
import '../../data/models/score_result.dart';

class ScoringUtils {
  // 이벤트 목록으로 최종 점수 산출 (100점 만점, 기존 대시보드용)
  static int calculateScore(List<DriveEvent> events) {
    int score = 100;

    for (final event in events) {
      switch (event.type) {
        case EventType.suddenAccel:
          score -= 5;
          break;
        case EventType.suddenBrake:
          score -= 5;
          break;
        case EventType.suddenSteering:
          score -= 3;
          break;
        case EventType.speeding:
          score -= 7;
          break;
        case EventType.hazardLight:
          score += 3; // 방어운전 가산
          break;
        default:
          break;
      }
    }

    return score.clamp(0, 100);
  }

  // 급가속 여부 판별 (기존 대시보드용 - RPM 기반)
  static bool isSuddenAccel(double prevRpm, double currRpm) {
    return (currRpm - prevRpm) > ObdConstants.suddenAccelRpmDelta;
  }

  // 급감속 여부 판별 (기존 대시보드용 - 속도 변화량 기반)
  static bool isSuddenBrake(double prevSpeed, double currSpeed) {
    return (prevSpeed - currSpeed) > ObdConstants.suddenBrakeKphDelta;
  }

  // 급조향 여부 판별 (도/초)
  static bool isSuddenSteering(double deltaAngle, double deltaTimeSec) {
    if (deltaTimeSec == 0) return false;
    return (deltaAngle.abs() / deltaTimeSec) > ObdConstants.steeringThreshold;
  }
}

/// 안전점수 실시간 계산 엔진
///
/// 1초마다 [DrivingSample]을 [processSample]로 전달하면
/// 새로 발생한 [DriveEvent] 목록을 반환하고 내부 점수를 갱신한다.
///
/// 이벤트 쿨타임: 같은 이벤트가 [ObdConstants.eventCooldownSec]초 이내 재발생하면 무시한다.
/// 지속 이벤트: 고RPM·공회전·엔진과부하는 일정 초 이상 지속될 때만 감점한다.
class DrivingScoreEngine {
  int _score = 100;
  final List<DriveEvent> _events = [];

  // 이벤트별 마지막 발생 시각 (쿨타임 관리)
  final Map<EventType, DateTime> _lastEventTime = {};

  // 지속 이벤트 카운터 (단위: 초)
  int _highRpmSeconds        = 0;
  int _idlingSeconds         = 0;
  int _engineOverloadSeconds = 0;

  int get score => _score;
  List<DriveEvent> get events => List.unmodifiable(_events);

  /// [current] 샘플과 직전 [previous] 샘플을 비교하여 이벤트를 판별한다.
  /// 새로 발생한 이벤트 목록을 반환한다.
  List<DriveEvent> processSample(DrivingSample current, DrivingSample? previous) {
    final newEvents = <DriveEvent>[];
    if (previous == null) return newEvents;

    final dt = current.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    if (dt <= 0) return newEvents;

    // ── 가속도 계산 ────────────────────────────────────────────────────
    // 급가속/급감속은 별도 OBD PID 없이 속도(010D) 변화량으로 계산
    // acceleration = ((currentSpeed - prevSpeed) / 3.6) / deltaTimeSec  [m/s²]
    final accel = ((current.speed - previous.speed) / 3.6) / dt;

    // A. 급가속 (acceleration >= 2.5 m/s²)
    if (accel >= ObdConstants.harshAccelThreshold) {
      final e = _tryAddEvent(
        type: EventType.harshAccel,
        title: '급가속',
        description: '가속도 ${accel.toStringAsFixed(1)} m/s²',
        penalty: ObdConstants.penaltyHarshAccel,
        value: accel,
      );
      if (e != null) newEvents.add(e);
    }

    // B. 급감속 (acceleration <= -3.0 m/s²)
    if (accel <= ObdConstants.harshBrakeThreshold) {
      final e = _tryAddEvent(
        type: EventType.harshBrake,
        title: '급감속',
        description: '감속도 ${accel.toStringAsFixed(1)} m/s²',
        penalty: ObdConstants.penaltyHarshBrake,
        value: accel,
      );
      if (e != null) newEvents.add(e);
    }

    // C. 급출발 (이전 속도 ≤ 3km/h + 스로틀 급변 ≥ 30% + RPM ≥ 3000)
    final throttleDeltaRaw = current.throttle - previous.throttle;
    if (previous.speed <= ObdConstants.idleSpeedThreshold &&
        throttleDeltaRaw >= ObdConstants.throttleSpikeThreshold &&
        current.rpm >= ObdConstants.hardStartRpmThreshold) {
      final e = _tryAddEvent(
        type: EventType.hardStart,
        title: '급출발',
        description: 'RPM ${current.rpm.toInt()}, 스로틀 +${throttleDeltaRaw.toInt()}%',
        penalty: ObdConstants.penaltyHardStart,
        value: current.rpm,
      );
      if (e != null) newEvents.add(e);
    }

    // D. 고RPM (3500rpm 이상 3초 이상 지속)
    if (current.rpm >= ObdConstants.highRpmThreshold) {
      _highRpmSeconds++;
      if (_highRpmSeconds >= ObdConstants.highRpmDurationSec) {
        final e = _tryAddEvent(
          type: EventType.highRpm,
          title: '고RPM 지속',
          description: 'RPM ${current.rpm.toInt()} / ${_highRpmSeconds}초 지속',
          penalty: ObdConstants.penaltyHighRpm,
          value: current.rpm,
        );
        if (e != null) {
          newEvents.add(e);
          _highRpmSeconds = 0; // 이벤트 발생 후 카운터 리셋
        }
      }
    } else {
      _highRpmSeconds = 0;
    }

    // E. 스로틀 급변 (변화량 절댓값 ≥ 30%)
    final throttleAbs = (current.throttle - previous.throttle).abs();
    if (throttleAbs >= ObdConstants.throttleSpikeThreshold) {
      final e = _tryAddEvent(
        type: EventType.throttleSpike,
        title: '스로틀 급변',
        description: '변화량 ${throttleAbs.toInt()}%',
        penalty: ObdConstants.penaltyThrottleSpike,
        value: throttleAbs,
      );
      if (e != null) newEvents.add(e);
    }

    // F. 공회전 (속도 ≤ 3km/h + RPM ≥ 700 이 60초 이상 지속)
    if (current.speed <= ObdConstants.idleSpeedThreshold &&
        current.rpm >= ObdConstants.idleRpmThreshold) {
      _idlingSeconds++;
      if (_idlingSeconds >= ObdConstants.idlingDurationSec) {
        final e = _tryAddEvent(
          type: EventType.idling,
          title: '장시간 공회전',
          description: '${_idlingSeconds}초 지속',
          penalty: ObdConstants.penaltyIdling,
          value: current.rpm,
        );
        if (e != null) {
          newEvents.add(e);
          _idlingSeconds = 0;
        }
      }
    } else {
      _idlingSeconds = 0;
    }

    // G. 엔진 과부하 (부하율 ≥ 80% 이 5초 이상 지속)
    if (current.engineLoad >= ObdConstants.engineLoadThreshold) {
      _engineOverloadSeconds++;
      if (_engineOverloadSeconds >= ObdConstants.engineOverloadDurationSec) {
        final e = _tryAddEvent(
          type: EventType.engineOverload,
          title: '엔진 과부하',
          description: '부하 ${current.engineLoad.toInt()}% / ${_engineOverloadSeconds}초 지속',
          penalty: ObdConstants.penaltyEngineOverload,
          value: current.engineLoad,
        );
        if (e != null) {
          newEvents.add(e);
          _engineOverloadSeconds = 0;
        }
      }
    } else {
      _engineOverloadSeconds = 0;
    }

    // TODO: ITS 교통소통정보 API를 활용해 현재 위치 기반 도로 제한속도 조회
    // TODO: GPS 좌표(gps_datasource.dart)와 ITS API 응답을 매칭하여 과속 여부 판단
    // TODO: 과속 이벤트(EventType.speeding)를 안전점수 감점 항목에 추가
    // TODO: API 키는 .env에서 로드하고 코드에 직접 작성하지 않음
    //       관련 파일: data/datasources/its_datasource.dart, gps_datasource.dart

    return newEvents;
  }

  /// 쿨타임을 확인하고, 통과하면 이벤트를 등록하고 점수를 감점한다.
  /// 쿨타임 내 재발생이면 null을 반환한다.
  DriveEvent? _tryAddEvent({
    required EventType type,
    required String title,
    required String description,
    required int penalty,
    required double value,
  }) {
    final now  = DateTime.now();
    final last = _lastEventTime[type];

    // 쿨타임 체크: 같은 이벤트가 5초 이내 재발생이면 무시
    if (last != null &&
        now.difference(last).inSeconds < ObdConstants.eventCooldownSec) {
      return null;
    }

    _lastEventTime[type] = now;
    final event = DriveEvent(
      type:        type,
      timestamp:   now,
      title:       title,
      description: description,
      penalty:     penalty,
      value:       value,
    );
    _events.add(event);
    _score = (_score - penalty).clamp(0, 100);
    return event;
  }

  /// 현재까지의 점수 결과를 [ScoreResult]로 반환한다.
  ScoreResult buildResult() => ScoreResult(
    score:               _score,
    totalPenalty:        100 - _score,
    harshAccelCount:     _count(EventType.harshAccel),
    harshBrakeCount:     _count(EventType.harshBrake),
    hardStartCount:      _count(EventType.hardStart),
    highRpmCount:        _count(EventType.highRpm),
    throttleSpikeCount:  _count(EventType.throttleSpike),
    idlingCount:         _count(EventType.idling),
    engineOverloadCount: _count(EventType.engineOverload),
    events:              List.unmodifiable(_events),
  );

  int _count(EventType type) => _events.where((e) => e.type == type).length;

  void reset() {
    _score = 100;
    _events.clear();
    _lastEventTime.clear();
    _highRpmSeconds        = 0;
    _idlingSeconds         = 0;
    _engineOverloadSeconds = 0;
  }
}