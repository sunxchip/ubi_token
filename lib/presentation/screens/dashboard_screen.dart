import 'package:flutter/material.dart';
import '../../data/datasources/obd_datasource.dart';
import '../../core/utils/scoring_utils.dart';
import '../../data/models/drive_event.dart';
import '../../core/constants/obd_constants.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ObdDatasource _obd = ObdDatasource();

  double _speed     = 0;
  double _rpm       = 0;
  double _steering  = 0;
  int    _score     = 100;
  bool   _isDriving = false;

  double _prevSpeed = 0;
  double _prevRpm   = 0;

  final List<DriveEvent> _events = [];
  final List<String> _eventLog   = [];

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) break;

      final speed = await _obd.getSpeed();
      final rpm   = await _obd.getRpm();

      setState(() {
        _prevSpeed = _speed;
        _prevRpm   = _rpm;
        _speed     = speed;
        _rpm       = rpm;
        _isDriving = rpm > 0;
      });

      _detectEvents(speed, rpm);
    }
  }

  void _detectEvents(double speed, double rpm) {
    // 급가속 감지
    if (ScoringUtils.isSuddenAccel(_prevRpm, rpm)) {
      _addEvent(EventType.suddenAccel, rpm, '급가속 감지!');
    }
    // 급감속 감지
    if (ScoringUtils.isSuddenBrake(_prevSpeed, speed)) {
      _addEvent(EventType.suddenBrake, speed, '급감속 감지!');
    }
  }

  void _addEvent(EventType type, double value, String log) {
    final event = DriveEvent(
      type: type,
      timestamp: DateTime.now(),
      latitude: 0,
      longitude: 0,
      value: value,
    );
    setState(() {
      _events.add(event);
      _eventLog.insert(0, '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} $log');
      _score = ScoringUtils.calculateScore(_events);
    });
  }

  @override
  void dispose() {
    _obd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('실시간 대시보드'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            // 주행 상태 표시
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _isDriving ? Colors.green[50] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isDriving ? Colors.green : Colors.grey[300]!,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      color: _isDriving ? Colors.green : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isDriving ? '주행 중' : '시동 대기',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isDriving ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 현재 점수
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Text(
                    '현재 점수',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_score',
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: _score >= 90
                          ? Colors.green
                          : _score >= 70
                          ? const Color(0xFFEF9F27)
                          : Colors.red,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 센서 데이터 그리드
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _SensorCard(
                  label: '속도',
                  value: '${_speed.toInt()}',
                  unit: 'km/h',
                  color: const Color(0xFF2563EB),
                ),
                _SensorCard(
                  label: 'RPM',
                  value: '${_rpm.toInt()}',
                  unit: 'rpm',
                  color: const Color(0xFF1D9E75),
                ),
                _SensorCard(
                  label: '조향각',
                  value: '${_steering.toStringAsFixed(1)}',
                  unit: '°',
                  color: const Color(0xFF7F77DD),
                ),
                _SensorCard(
                  label: '이벤트',
                  value: '${_events.length}',
                  unit: '건',
                  color: const Color(0xFFD85A30),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 이벤트 로그
            if (_eventLog.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '이벤트 로그',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B3A5C),
                  ),
                ),
              ),
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
                  children: _eventLog.take(5).map((log) =>
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 14, color: Colors.orange),
                            const SizedBox(width: 8),
                            Text(log, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                  ).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Container(
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
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  unit,
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}