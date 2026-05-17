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
  // 전역 연결 인스턴스 사용 (ScannerConnectScreen에서 connect() 후 자동 등록)
  ObdDatasource? get _obd => ObdDatasource.connected;

  double _speed    = 0;
  double _rpm      = 0;
  double _steering = 0;
  TurnSignalState _signals = const TurnSignalState(left: false, right: false, hazard: false);
  int    _score    = 100;
  bool   _isDriving = false;

  double _prevSpeed = 0;
  double _prevRpm   = 0;
  double _prevSteering = 0;
  int    _prevSteeringMs = 0;

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

      final speed    = await _obd!.getSpeed();
      final rpm      = await _obd!.getRpm();
      final steering = await _obd!.getSteeringAngle();
      final signals  = await _obd!.getTurnSignals();

      if (!mounted) break;

      final now = DateTime.now().millisecondsSinceEpoch;
      final wasDriving = _isDriving;

      setState(() {
        _prevSpeed    = _speed;
        _prevRpm      = _rpm;
        _prevSteering = _steering;
        _prevSteeringMs = _prevSteeringMs == 0 ? now : _prevSteeringMs;
        _speed    = speed;
        _rpm      = rpm;
        _steering = steering;
        _signals  = signals;
        _isDriving = rpm > 0;
        _prevSteeringMs = now;
      });

      if (!wasDriving && _isDriving) await _startSession();
      if (wasDriving && !_isDriving) await _endSession();

      _detectEvents(speed, rpm, steering, signals, now);
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
    final session = sessions.where((s) => s.sessionId == sessionId).firstOrNull;
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

  void _detectEvents(double speed, double rpm, double steering,
      TurnSignalState signals, int nowMs) {
    // 급가속
    if (ScoringUtils.isSuddenAccel(_prevRpm, rpm)) {
      _addEvent(EventType.suddenAccel, rpm, '급가속 감지');
    }
    // 급감속
    if (ScoringUtils.isSuddenBrake(_prevSpeed, speed)) {
      _addEvent(EventType.suddenBrake, speed, '급감속 감지');
      // 급감속 + 비상등 → 방어운전 가산
      if (signals.hazard) {
        _addEvent(EventType.hazardLight, speed, '방어운전 (비상등)');
      }
    }
    // 급조향
    if (_prevSteeringMs > 0) {
      final dtSec = (nowMs - _prevSteeringMs) / 1000.0;
      if (ScoringUtils.isSuddenSteering(steering - _prevSteering, dtSec)) {
        _addEvent(EventType.suddenSteering, steering, '급조향 감지');
      }
    }
  }

  void _addEvent(EventType type, double value, String log) {
    final now = DateTime.now();
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
                  // 주행 상태 + 점수 row
                  _StatusScoreRow(isDriving: _isDriving, score: _score, scoreColor: _scoreColor),
                  const SizedBox(height: 12),

                  // 방향지시등
                  _TurnSignalBar(signals: _signals),
                  const SizedBox(height: 12),

                  // 센서 그리드
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
                      _SensorCard(label: '조향각', value: _steering.toStringAsFixed(1), unit: '°', color: const Color(0xFF7C3AED)),
                      _SensorCard(label: '이벤트', value: '${_events.length}', unit: '건', color: AppColors.danger),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 이벤트 로그
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
  const _StatusScoreRow({required this.isDriving, required this.score, required this.scoreColor});

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
            // 주행 상태
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
            // 현재 점수
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

class _TurnSignalBar extends StatelessWidget {
  final TurnSignalState signals;
  const _TurnSignalBar({required this.signals});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SignalDot(label: '좌회전', active: signals.left,   color: AppColors.warning),
            _SignalDot(label: '비상등', active: signals.hazard, color: AppColors.danger),
            _SignalDot(label: '우회전', active: signals.right,  color: AppColors.warning),
          ],
        ),
      );
}

class _SignalDot extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  const _SignalDot({required this.label, required this.active, required this.color});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : AppColors.border,
              boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 5)] : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: active ? color : AppColors.textHint,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      );
}

class _SensorCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _SensorCard({required this.label, required this.value, required this.unit, required this.color});

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
                Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color)),
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
                const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(log, style: AppTextStyles.body)),
              ],
            ),
          )).toList(),
        ),
      );
}
