import 'package:drift/drift.dart' show Value;
import '../database/app_database.dart' as db;
import '../models/drive_event.dart';
import '../models/score_result.dart';

/// 주행 세션 저장/조회 Repository
///
/// 기존 [AppDatabase] 스키마(TripSessions, DriveEvents)를 그대로 활용한다.
/// 스키마 변경(마이그레이션) 없이 안전점수 데이터를 저장하기 위해
/// 이벤트별 횟수·총 감점은 조회 시 DriveEvents 테이블에서 파생한다.
///
/// history_screen.dart는 [AppDatabase.getAllSessions()]로 세션 목록을 표시하고,
/// 상세 화면에서 [getScoreResultBySessionId()]로 분석 데이터를 로드할 수 있다.
class TripSessionRepository {
  TripSessionRepository._();
  static final TripSessionRepository instance = TripSessionRepository._();

  final _database = db.AppDatabase.instance;

  // ── 저장 ─────────────────────────────────────────────────────────────────
  /// [ScoreResult]와 주행 메타데이터를 DB에 저장한다.
  ///
  /// 저장 구조:
  ///   TripSessions 테이블: sessionId, startTime, endTime, finalScore
  ///   DriveEvents  테이블: 이벤트별 type(index), timestamp, value
  ///
  /// [sampleCount] 는 추후 distanceKm 계산에 활용할 수 있도록 value에 임시 저장
  /// TODO: GPS datasource와 연동하여 실제 이동 거리(distanceKm) 계산
  Future<String> saveScoreResult({
    required ScoreResult result,
    required String vin,
    required DateTime startTime,
    required DateTime endTime,
    int sampleCount = 0,
  }) async {
    final sessionId = startTime.millisecondsSinceEpoch.toString();

    // 1. 세션 저장
    await _database.insertSession(db.TripSessionsCompanion(
      sessionId:  Value(sessionId),
      startTime:  Value(startTime.millisecondsSinceEpoch),
      endTime:    Value(endTime.millisecondsSinceEpoch),
      distanceKm: const Value(0.0), // TODO: GPS 연동 후 실거리로 교체
      finalScore: Value(result.score),
    ));

    // 2. 이벤트 저장
    for (final event in result.events) {
      await _database.insertEvent(db.DriveEventsCompanion(
        sessionId: Value(sessionId),
        type:      Value(event.type.index), // EventType.harshAccel.index = 5, etc.
        timestamp: Value(event.timestamp.millisecondsSinceEpoch),
        latitude:  const Value(0.0), // TODO: GPS 연동 후 실좌표로 교체
        longitude: const Value(0.0),
        value:     Value(event.value),
      ));
    }

    return sessionId;
  }

  // ── 조회 ─────────────────────────────────────────────────────────────────
  /// 최근 N개 세션 목록 반환 (history_screen에서 사용)
  Future<List<db.TripSession>> getRecentSessions({int limit = 20}) =>
      _database.getRecentSessions(limit: limit);

  /// 전체 세션 목록 (최신순)
  Future<List<db.TripSession>> getAllSessions() =>
      _database.getAllSessions();

  /// 세션 ID로 [ScoreResult] 재구성
  ///
  /// DriveEvents 테이블에서 이벤트를 조회하고 EventType.index로 역변환한다.
  /// 추후 history_screen 상세 화면에서 감점 내역을 표시할 때 활용한다.
  Future<ScoreResult?> getScoreResultBySessionId(String sessionId) async {
    final sessions = await _database.getAllSessions();
    final session  = sessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (session == null) return null;

    final dbEvents = await _database.getEventsBySession(sessionId);

    // DB의 DriveEvent(Drift 생성) → 모델 DriveEvent로 변환
    final events = dbEvents.map((e) {
      final type = e.type < EventType.values.length
          ? EventType.values[e.type]
          : EventType.suddenAccel;
      return DriveEvent(
        type:      type,
        timestamp: DateTime.fromMillisecondsSinceEpoch(e.timestamp),
        latitude:  e.latitude,
        longitude: e.longitude,
        value:     e.value,
        title:     _titleForType(type),
        penalty:   _penaltyForType(type),
      );
    }).toList();

    return ScoreResult(
      score:               session.finalScore,
      totalPenalty:        100 - session.finalScore,
      harshAccelCount:     events.where((e) => e.type == EventType.harshAccel).length,
      harshBrakeCount:     events.where((e) => e.type == EventType.harshBrake).length,
      hardStartCount:      events.where((e) => e.type == EventType.hardStart).length,
      highRpmCount:        events.where((e) => e.type == EventType.highRpm).length,
      throttleSpikeCount:  events.where((e) => e.type == EventType.throttleSpike).length,
      idlingCount:         events.where((e) => e.type == EventType.idling).length,
      engineOverloadCount: events.where((e) => e.type == EventType.engineOverload).length,
      events:              events,
    );
  }

  // ── 헬퍼 ─────────────────────────────────────────────────────────────────
  String _titleForType(EventType type) {
    switch (type) {
      case EventType.harshAccel:     return '급가속';
      case EventType.harshBrake:     return '급감속';
      case EventType.hardStart:      return '급출발';
      case EventType.highRpm:        return '고RPM 지속';
      case EventType.throttleSpike:  return '스로틀 급변';
      case EventType.idling:         return '장시간 공회전';
      case EventType.engineOverload: return '엔진 과부하';
      default:                       return type.name;
    }
  }

  int _penaltyForType(EventType type) {
    switch (type) {
      case EventType.harshAccel:     return 3;
      case EventType.harshBrake:     return 4;
      case EventType.hardStart:      return 4;
      case EventType.highRpm:        return 2;
      case EventType.throttleSpike:  return 2;
      case EventType.idling:         return 2;
      case EventType.engineOverload: return 2;
      default:                       return 0;
    }
  }
}
