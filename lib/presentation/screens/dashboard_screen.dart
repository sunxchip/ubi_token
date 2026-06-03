import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import '../../data/database/app_database.dart' as db;
import '../../data/datasources/obd_datasource.dart';
import '../../core/utils/scoring_utils.dart';
import '../../data/models/drive_event.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  ObdDatasource? get _obd => ObdDatasource.connected;

  double _speed      = 0;
  double _rpm        = 0;
  double _throttle   = 0;
  double _engineLoad = 0;
  int    _score      = 100;
  bool   _isDriving  = false;

  double _prevSpeed = 0;
  double _prevRpm   = 0;

  final List<DriveEvent> _events   = [];
  final List<String>     _eventLog = [];

  String? _currentSessionId;
  final _db = db.AppDatabase.instance;

  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() async {
    if (_obd == null) return;
    _isPolling = true;

    while (mounted && _isPolling) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || _obd == null) break;

      final speed      = await _obd!.getSpeed();
      final rpm        = await _obd!.getRpm();
      final throttle   = await _obd!.getThrottle();
      final engineLoad = await _obd!.getEngineLoad();

      if (!mounted) break;

      final wasDriving = _isDriving;

      setState(() {
        _prevSpeed = _speed;
        _prevRpm   = _rpm;
        _speed      = speed;
        _rpm        = rpm;
        _throttle   = throttle;
        _engineLoad = engineLoad;
        _isDriving  = rpm > 0;
      });

      if (!wasDriving && _isDriving) await _startSession();
      if (wasDriving && !_isDriving) await _endSession();

      _detectEvents(speed, rpm);
    }
  }

  Future<void> _startSession() async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    await _db.insertSession(db.TripSessionsCompanion(
      sessionId:  Value(sessionId),
      startTime:  Value(DateTime.now().millisecondsSinceEpoch),
      finalScore: Value(100),
    ));
    setState(() {
      _currentSessionId = sessionId;
      _events.clear();
      _eventLog.clear();
      _score = 100;
    });
  }

  Future<void> _endSession() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) return;
    final sessions = await _db.getAllSessions();
    final session  = sessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (session == null) return;
    await _db.updateSession(db.TripSessionsCompanion(
      id:         Value(session.id),
      sessionId:  Value(session.sessionId),
      startTime:  Value(session.startTime),
      endTime:    Value(DateTime.now().millisecondsSinceEpoch),
      distanceKm: Value(session.distanceKm),
      finalScore: Value(_score),
    ));
    setState(() => _currentSessionId = null);
  }

  // 표준 OBD-II PID 기반 이벤트 감지 (속도·RPM 변화량)
  // 조향각·방향지시등·브레이크 기반 이벤트는 제거됨
  void _detectEvents(double speed, double rpm) {
    if (ScoringUtils.isSuddenAccel(_prevRpm, rpm)) {
      _addEvent(EventType.suddenAccel, rpm, '급가속 감지');
    }
    if (ScoringUtils.isSuddenBrake(_prevSpeed, speed)) {
      _addEvent(EventType.suddenBrake, speed, '급감속 감지');
    }
  }

  void _addEvent(EventType type, double value, String log) {
    final now   = DateTime.now();
    final event = DriveEvent(
      type: type, timestamp: now,
      latitude: 0, longitude: 0, value: value,
    );
    setState(() {
      _events.add(event);
      _eventLog.insert(0,
          '${now.hour}:${now.minute.toString().padLeft(2, '0')} $log');
      _score = ScoringUtils.calculateScore(_events);
    });
    final sessionId = _currentSessionId;
    if (sessionId != null) {
      _db.insertEvent(db.DriveEventsCompanion(
        sessionId: Value(sessionId),
        type:      Value(type.index),
        timestamp: Value(now.millisecondsSinceEpoch),
        latitude:  Value(0.0),
        longitude: Value(0.0),
        value:     Value(value),
      ));
    }
  }

  @override
  void dispose() {
    _isPolling = false;
    super.dispose();
  }

  Color _scoreColor(int score) {
    if (score >= 90) return AppColors.success;
    if (score >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final connected = _obd != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('실시간 대시보드', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: !connected
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bluetooth_disabled, size: 36, color: AppColors.textHint),
                  SizedBox(height: 12),
                  Text('OBD 장치에 먼저 연결해주세요', style: AppTextStyles.bodySecondary),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusScoreRow(
                    isDriving: _isDriving,
                    score: _score,
                    scoreColor: _scoreColor,
                  ),
                  const SizedBox(height: 12),

                  // 표준 OBD-II PID 읽기 전용 안내
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Text(
                      '표준 OBD-II 읽기 전용 모드 · 제어 명령 없음',
                      style: TextStyle(fontSize: 11, color: AppColors.primary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),

                  const Text('센서 데이터', style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.5,
                    children: [
                      _SensorCard(label: '속도', value: '${_speed.toInt()}', unit: 'km/h', color: AppColors.primary),
                      _SensorCard(label: 'RPM', value: '${_rpm.toInt()}', unit: 'rpm', color: AppColors.success),
                      _SensorCard(label: '스로틀', value: _throttle.toStringAsFixed(1), unit: '%', color: AppColors.warning),
                      _SensorCard(label: '엔진부하', value: _engineLoad.toStringAsFixed(1), unit: '%', color: AppColors.danger),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (_eventLog.isNotEmpty) ...[
                    const Text('이벤트 로그', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    _EventLog(logs: _eventLog),
                  ],
                ],
              ),
            ),
    );
  }
}

// ── 공용 위젯 ──────────────────────────────────────────

class _StatusScoreRow extends StatelessWidget {
  final bool isDriving;
  final int score;
  final Color Function(int) scoreColor;
  const _StatusScoreRow({
    required this.isDriving,
    required this.score,
    required this.scoreColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isDriving ? AppColors.success : AppColors.textHint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isDriving ? '주행 중' : '시동 대기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDriving ? AppColors.success : AppColors.textHint,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('현재 점수', style: AppTextStyles.caption),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: scoreColor(score),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _SensorCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.caption),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit, style: AppTextStyles.captionHint),
                ),
              ],
            ),
          ],
        ),
      );
}

class _EventLog extends StatelessWidget {
  final List<String> logs;
  const _EventLog({required this.logs});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Column(
          children: logs.take(5).map((log) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(log, style: AppTextStyles.body)),
              ],
            ),
          )).toList(),
        ),
      );
}
