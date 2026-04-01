import '../constants/obd_constants.dart';
import '../../data/models/drive_event.dart';

class ScoringUtils {
  // 이벤트 목록으로 최종 점수 산출 (100점 만점)
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
      }
    }

    return score.clamp(0, 100);
  }

  // 급가속 여부 판별
  static bool isSuddenAccel(double prevRpm, double currRpm) {
    return (currRpm - prevRpm) > ObdConstants.suddenAccelRpmDelta;
  }

  // 급감속 여부 판별
  static bool isSuddenBrake(double prevSpeed, double currSpeed) {
    return (prevSpeed - currSpeed) > ObdConstants.suddenBrakeKphDelta;
  }

  // 급조향 여부 판별 (도/초)
  static bool isSuddenSteering(double deltaAngle, double deltaTimeSec) {
    if (deltaTimeSec == 0) return false;
    return (deltaAngle.abs() / deltaTimeSec) > ObdConstants.steeringThreshold;
  }
}