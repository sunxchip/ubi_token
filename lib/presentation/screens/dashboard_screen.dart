import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import '../../data/database/app_database.dart' as db;
import '../../data/datasources/obd_datasource.dart';
import '../../core/utils/scoring_utils.dart';
import '../../data/models/drive_event.dart';

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

  @override
  Widget build(BuildContext context) {
    final connected = _obd != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('실시간 대시보드'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: !connected
          ? const Center(child: Text('OBD 장치에 먼저 연결해주세요',
              style: TextStyle(color: Colors.grey)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // 주행 상태
                  _StatusBanner(isDriving: _isDriving, sessionId: _currentSessionId),
                  const SizedBox(height: 12),

                  // 점수
                  _ScoreCard(score: _score),
                  const SizedBox(height: 12),

                  // 방향지시등 (실차 검증 필요 - 값이 맞지 않으면 PID 진단 화면에서 확인)
                  _TurnSignalBar(signals: _signals),
                  const SizedBox(height: 12),

                  // 센서 그리드
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _SensorCard(label: '속도', value: '${_speed.toInt()}',
                          unit: 'km/h', color: const Color(0xFF2563EB)),
                      _SensorCard(label: 'RPM', value: '${_rpm.toInt()}',
                          unit: 'rpm', color: const Color(0xFF1D9E75)),
                      _SensorCard(
                          label: '조향각',
                          value: _steering.toStringAsFixed(1),
                          unit: '°',
                          color: const Color(0xFF7F77DD)),
                      _SensorCard(label: '이벤트', value: '${_events.length}',
                          unit: '건', color: const Color(0xFFD85A30)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 이벤트 로그
                  if (_eventLog.isNotEmpty) _EventLog(logs: _eventLog),
                ],
              ),
            ),
    );
  }
}

// ── 공용 위젯 ──────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final bool isDriving;
  final String? sessionId;
  const _StatusBanner({required this.isDriving, this.sessionId});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDriving ? Colors.green[50] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDriving ? Colors.green : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: isDriving ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isDriving ? '주행 중' : '시동 대기',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDriving ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      );
}

class _ScoreCard extends StatelessWidget {
  final int score;
  const _ScoreCard({required this.score});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          children: [
            Text('현재 점수', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(
              '$score',
              style: TextStyle(
                fontSize: 48, fontWeight: FontWeight.bold,
                color: score >= 90 ? Colors.green
                    : score >= 70 ? const Color(0xFFEF9F27)
                    : Colors.red,
              ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SignalDot(label: '◀ 좌', active: signals.left,   color: Colors.orange),
            _SignalDot(label: '비상', active: signals.hazard, color: Colors.red),
            _SignalDot(label: '우 ▶', active: signals.right,  color: Colors.orange),
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
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 12, height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? color : Colors.grey[200],
              boxShadow: active ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 13,
            color: active ? color : Colors.grey,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          )),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(unit, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('이벤트 로그',
              style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B3A5C))),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: logs.take(5).map((log) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text(log, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      );
}
