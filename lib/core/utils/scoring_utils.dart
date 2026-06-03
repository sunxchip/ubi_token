import '../constants/obd_constants.dart';
import '../../data/models/drive_event.dart';
import '../../data/models/driving_sample.dart';
import '../../data/models/score_result.dart';
import 'drive_tracking_state_machine.dart';

class ScoringUtils {
  // 이벤트 목록으로 최종 점수 산출 (100점 만점, 기존 대시보드용)
  // 조향각 및 방향지시등 이벤트는 제거되어 이 함수에서 처리하지 않음
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
        case EventType.speeding:
          score -= 7;
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

  // 참고: isSuddenSteering()은 제조사 고유 CAN 신호(조향각)가 필요하므로 제거됨
}

/// 안전점수 실시간 계산 엔진
///
/// 표준 OBD-II PID 기반으로만 동작한다:
///   010D Vehicle Speed, 010C Engine RPM,
///   0111 Throttle Position, 0104 Engine Load
///
/// 제외 항목: 조향각, 방향지시등, 브레이크 압력, 변속 상태, 휠스피드,
///           ABS/ESC, 차체 CAN 신호
class DrivingScoreEngine {
  int _score = 100;
  final List<DriveEvent> _events = [];

  final Map<EventType, DateTime> _lastEventTime = {};

  int _highRpmSeconds        = 0;
  int _idlingSeconds         = 0;
  int _engineOverloadSeconds = 0;

  int get score => _score;
  List<DriveEvent> get events => List.unmodifiable(_events);

  List<DriveEvent> processSample(
    DrivingSample current,
    DrivingSample? previous, {
    DriveTrackingState trackingState = DriveTrackingState.driving,
  }) {
    final newEvents = <DriveEvent>[];
    if (previous == null) return newEvents;

    final dt = current.timestamp.difference(previous.timestamp).inMilliseconds / 1000.0;
    if (dt <= 0) return newEvents;

    if (trackingState == DriveTrackingState.driving) {
      final accel = ((current.speed - previous.speed) / 3.6) / dt;

      // A. 급가속 (acceleration >= 2.5 m/s²)
      if (accel >= ObdConstants.harshAccelThreshold) {
        final e = _tryAddEvent(
          type: EventType.harshAccel,
          title: '급가속',
          description: '짧은 시간 내 속도가 급격히 증가했습니다. (가속도 ${accel.toStringAsFixed(1)} m/s²)',
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
          description: '짧은 시간 내 속도가 급격히 감소했습니다. (감속도 ${accel.toStringAsFixed(1)} m/s²)',
          penalty: ObdConstants.penaltyHarshBrake,
          value: accel,
        );
        if (e != null) newEvents.add(e);
      }

      // C. 급출발 (이전 속도 ≤ 3km/h + 스로틀 급변 ≥ 30% + RPM ≥ 3000)
      final throttleDelta = current.throttle - previous.throttle;
      if (previous.speed <= ObdConstants.idleSpeedThreshold &&
          throttleDelta >= ObdConstants.throttleSpikeThreshold &&
          current.rpm >= ObdConstants.hardStartRpmThreshold) {
        final e = _tryAddEvent(
          type: EventType.hardStart,
          title: '급출발',
          description: '정차 상태에서 스로틀과 RPM이 급격히 상승했습니다.',
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
            description: '높은 RPM 상태가 지속되었습니다. (RPM ${current.rpm.toInt()}, ${_highRpmSeconds}초 지속)',
            penalty: ObdConstants.penaltyHighRpm,
            value: current.rpm,
          );
          if (e != null) {
            newEvents.add(e);
            _highRpmSeconds = 0;
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
          description: '가속 페달 조작이 급격하게 변화했습니다. (변화량 ${throttleAbs.toInt()}%)',
          penalty: ObdConstants.penaltyThrottleSpike,
          value: throttleAbs,
        );
        if (e != null) newEvents.add(e);
      }

      // F. 엔진 과부하 (부하율 ≥ 80% 이 5초 이상 지속)
      if (current.engineLoad >= ObdConstants.engineLoadThreshold) {
        _engineOverloadSeconds++;
        if (_engineOverloadSeconds >= ObdConstants.engineOverloadDurationSec) {
          final e = _tryAddEvent(
            type: EventType.engineOverload,
            title: '엔진 과부하',
            description: '엔진 부하가 높은 상태가 지속되었습니다. (부하 ${current.engineLoad.toInt()}%, ${_engineOverloadSeconds}초 지속)',
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
    } else {
      _highRpmSeconds        = 0;
      _engineOverloadSeconds = 0;
    }

    // 공회전 감점
    final isIdlingState = trackingState == DriveTrackingState.engineOn ||
                          trackingState == DriveTrackingState.stopped;
    if (isIdlingState &&
        current.speed <= ObdConstants.idleSpeedThreshold &&
        current.rpm >= ObdConstants.idleRpmThreshold) {
      _idlingSeconds++;
      if (_idlingSeconds >= ObdConstants.idlingDurationSec) {
        final e = _tryAddEvent(
          type: EventType.idling,
          title: '장시간 공회전',
          description: '정차 상태에서 엔진 구동이 오래 지속되었습니다.',
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

    // TODO: ITS API 기반 과속 감점 (위치 기반 제한속도 연동 후 추가 예정)

    return newEvents;
  }

  DriveEvent? _tryAddEvent({
    required EventType type,
    required String title,
    required String description,
    required int penalty,
    required double value,
  }) {
    final now  = DateTime.now();
    final last = _lastEventTime[type];

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
