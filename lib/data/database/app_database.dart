import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// 주행 세션 테이블
class TripSessions extends Table {
  IntColumn get id          => integer().autoIncrement()();
  TextColumn get sessionId  => text()();
  IntColumn get startTime   => integer()();
  IntColumn get endTime     => integer().nullable()();
  RealColumn get distanceKm => real().withDefault(const Constant(0.0))();
  IntColumn get finalScore  => integer().withDefault(const Constant(100))();
}

// 이벤트 테이블
class DriveEvents extends Table {
  IntColumn get id        => integer().autoIncrement()();
  TextColumn get sessionId => text()();
  IntColumn get type      => integer()();
  IntColumn get timestamp => integer()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  RealColumn get value    => real()();
}

@DriftDatabase(tables: [TripSessions, DriveEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'ubi_token_db');
  }

  // 세션 저장
  Future<int> insertSession(TripSessionsCompanion session) =>
      into(tripSessions).insert(session);

  // 세션 업데이트 (종료 시)
  Future<bool> updateSession(TripSessionsCompanion session) =>
      update(tripSessions).replace(session);

  // 전체 세션 조회 (최신순)
  Future<List<TripSession>> getAllSessions() =>
      (select(tripSessions)
        ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
          .get();

  // 이벤트 저장
  Future<int> insertEvent(DriveEventsCompanion event) =>
      into(driveEvents).insert(event);

  // 세션별 이벤트 조회
  Future<List<DriveEvent>> getEventsBySession(String sessionId) =>
      (select(driveEvents)
        ..where((e) => e.sessionId.equals(sessionId)))
          .get();

  // 최근 7개 세션 조회
  Future<List<TripSession>> getRecentSessions({int limit = 7}) =>
      (select(tripSessions)
        ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
        ..limit(limit))
          .get();
}