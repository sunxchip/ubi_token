import 'drive_event.dart';

/// 주행 종료 후 최종 안전점수 산출 결과
class ScoreResult {
  final int score;              // 최종 점수 (0~100)
  final int totalPenalty;       // 총 감점
  final int harshAccelCount;    // 급가속 횟수
  final int harshBrakeCount;    // 급감속 횟수
  final int hardStartCount;     // 급출발 횟수
  final int highRpmCount;       // 고RPM 지속 횟수
  final int throttleSpikeCount; // 스로틀 급변 횟수
  final int idlingCount;        // 공회전 횟수
  final int engineOverloadCount; // 엔진 과부하 횟수
  final List<DriveEvent> events; // 전체 이벤트 목록

  const ScoreResult({
    required this.score,
    required this.totalPenalty,
    required this.harshAccelCount,
    required this.harshBrakeCount,
    required this.hardStartCount,
    required this.highRpmCount,
    required this.throttleSpikeCount,
    required this.idlingCount,
    required this.engineOverloadCount,
    required this.events,
  });

  String get grade {
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 60) return 'D';
    return 'F';
  }

  String get gradeLabel {
    if (score >= 90) return '우수한 운전 습관';
    if (score >= 80) return '양호한 운전 습관';
    if (score >= 70) return '보통 수준';
    if (score >= 60) return '개선이 필요해요';
    return '운전 습관 개선이 시급해요';
  }
}
