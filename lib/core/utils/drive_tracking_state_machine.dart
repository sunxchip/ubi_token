import '../../data/models/driving_sample.dart';

/// 주행 세션 자동 감지를 위한 상태 머신
///
/// RPM + 차량 속도 + OBD 연결 상태를 조합해 주행 세션의 시작/종료를 판단한다.
///
/// 상태 전이:
///   idle       → engineOn  : RPM >= 500
///   engineOn   → driving   : speed >= 5km/h 가 3초 이상 지속
///   driving    → stopped   : speed <= 3km/h (신호대기·정차)
///   stopped    → driving   : speed >= 5km/h 가 3초 이상 지속 (재출발)
///   any        → tripEnded : OBD 끊김 / RPM==0 30초 / stopped 5분 이상
///   tripEnded  → idle      : 자동 리셋 (다음 사이클)
enum DriveTrackingState {
  idle,       // OBD 없음 또는 RPM 0 & speed 0
  engineOn,   // 시동 켜짐, 주행 전 (RPM >= 500, speed <= 3)
  driving,    // 주행 중 → 안전점수 측정 세션 활성
  stopped,    // 정차 중 (신호대기 / 오토스탑) → 세션 유지
  tripEnded,  // 주행 세션 종료
}

extension DriveTrackingStateLabel on DriveTrackingState {
  String get label {
    switch (this) {
      case DriveTrackingState.idle:      return 'OBD 대기';
      case DriveTrackingState.engineOn:  return '시동 감지';
      case DriveTrackingState.driving:   return '주행 중';
      case DriveTrackingState.stopped:   return '정차 중';
      case DriveTrackingState.tripEnded: return '주행 종료';
    }
  }
}

class DriveTrackingStateMachine {
  DriveTrackingState _state = DriveTrackingState.idle;
  DriveTrackingState get state => _state;

  // ── 지속 시간 카운터 (단위: 초, 1초 샘플 기준) ──────────────────────────────
  int _speedAbove5Seconds = 0; // engineOn/stopped → driving 진입 판단
  int _rpmZeroSeconds     = 0; // RPM 0 지속 (시동 꺼짐/ISG 판단)
  int _stoppedSeconds     = 0; // stopped 상태 지속 (5분 초과 시 세션 종료)

  /// 샘플을 처리하고 상태가 전이되면 새 상태를 반환한다.
  /// 상태 변화가 없으면 null 반환.
  DriveTrackingState? process(DrivingSample sample, {bool isObdConnected = true}) {
    final prev = _state;
    _state = _computeNext(sample, isObdConnected);
    return _state != prev ? _state : null;
  }

  DriveTrackingState _computeNext(DrivingSample sample, bool isObdConnected) {
    // OBD 연결 끊김 → 주행 중이었으면 tripEnded, 아니면 idle
    if (!isObdConnected) {
      final wasActive = _state == DriveTrackingState.driving ||
                        _state == DriveTrackingState.stopped;
      _resetCounters();
      return wasActive ? DriveTrackingState.tripEnded : DriveTrackingState.idle;
    }

    // RPM 0 지속 카운터 (ISG 오토스탑 포함)
    if (sample.rpm < 100) {
      _rpmZeroSeconds++;
    } else {
      _rpmZeroSeconds = 0;
    }

    switch (_state) {
      case DriveTrackingState.idle:
        _speedAbove5Seconds = 0;
        _stoppedSeconds     = 0;
        if (sample.rpm >= 500) return DriveTrackingState.engineOn;
        return DriveTrackingState.idle;

      case DriveTrackingState.engineOn:
        _stoppedSeconds = 0;
        // 시동 꺼짐 (RPM ≈ 0 & speed ≈ 0)
        if (sample.rpm < 100 && sample.speed < 1) {
          _resetCounters();
          return DriveTrackingState.idle;
        }
        // 주행 진입: speed >= 5km/h 가 3초 이상
        if (sample.speed >= 5) {
          _speedAbove5Seconds++;
          if (_speedAbove5Seconds >= 3) return DriveTrackingState.driving;
        } else {
          _speedAbove5Seconds = 0;
        }
        return DriveTrackingState.engineOn;

      case DriveTrackingState.driving:
        // RPM 0이 30초 이상 → 시동 꺼짐으로 판단 (ISG 포함)
        if (_rpmZeroSeconds >= 30) {
          _resetCounters();
          return DriveTrackingState.tripEnded;
        }
        // 정차 감지: speed <= 3km/h
        // 주의: ISG로 RPM 0이 되어도 바로 종료하지 않고 stopped로 이동
        if (sample.speed <= 3) {
          _speedAbove5Seconds = 0;
          _stoppedSeconds     = 0;
          return DriveTrackingState.stopped;
        }
        return DriveTrackingState.driving;

      case DriveTrackingState.stopped:
        _stoppedSeconds++;
        // 정차 5분(300초) 이상 → 세션 종료
        if (_stoppedSeconds >= 300) {
          _resetCounters();
          return DriveTrackingState.tripEnded;
        }
        // RPM 0 30초 이상 → ISG 시동 꺼짐으로 판단 → 세션 종료
        if (_rpmZeroSeconds >= 30) {
          _resetCounters();
          return DriveTrackingState.tripEnded;
        }
        // 재출발: speed >= 5km/h 가 3초 이상
        if (sample.speed >= 5) {
          _speedAbove5Seconds++;
          if (_speedAbove5Seconds >= 3) {
            _stoppedSeconds = 0;
            return DriveTrackingState.driving;
          }
        } else {
          _speedAbove5Seconds = 0;
        }
        return DriveTrackingState.stopped;

      case DriveTrackingState.tripEnded:
        // 다음 사이클에서 자동으로 idle로 전환
        _resetCounters();
        return DriveTrackingState.idle;
    }
  }

  void _resetCounters() {
    _speedAbove5Seconds = 0;
    _rpmZeroSeconds     = 0;
    _stoppedSeconds     = 0;
  }

  void reset() {
    _state = DriveTrackingState.idle;
    _resetCounters();
  }
}
