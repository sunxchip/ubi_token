import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/driving_data_source.dart';
import '../../data/models/driving_sample.dart';
import '../../data/models/drive_event.dart';
import '../../data/models/score_result.dart';
import '../../core/utils/scoring_utils.dart';
import '../../data/repositories/trip_session_repository.dart';
import 'driving_score_result_screen.dart';

class DrivingScoreScreen extends StatefulWidget {
  const DrivingScoreScreen({super.key});

  @override
  State<DrivingScoreScreen> createState() => _DrivingScoreScreenState();
}

class _DrivingScoreScreenState extends State<DrivingScoreScreen> {
  // ── VIN 인증 상태 ─────────────────────────────────────────────────────────
  // VIN 인증 성공 시 vin_auth_screen.dart가 SharedPreferences에
  // 'auth_token', 'vin', 'car_model' 키를 저장한다.
  //
  // TODO: 기존 VIN 인증 결과 Provider/Service/State와 연결
  // TODO: 현재 임시로 SharedPreferences 기반 isVinVerified를 사용하며,
  //       실제 VIN 인증 결과 상태 관리 클래스로 교체 필요
  String _vin          = '';
  String _carModel     = '';
  bool   _isVinVerified = false;

  // ── 주행 상태 ─────────────────────────────────────────────────────────────
  bool _isDriving = false;
  DrivingSample? _currentSample;
  DrivingSample? _prevSample;
  DateTime? _startTime;
  final List<DriveEvent> _recentEvents = [];
  final DrivingScoreEngine _scoreEngine = DrivingScoreEngine();

  // ── 시나리오 선택 ─────────────────────────────────────────────────────────
  // TODO: 실제 RealObdDataSource로 전환 시 이 변수와 시나리오 드롭다운 UI를 숨길 것
  MockDriveScenario _selectedScenario = MockDriveScenario.risky;

  // ── 데이터 소스 ───────────────────────────────────────────────────────────
  // TODO: 실제 ELM327 연결 시 아래 한 줄만 교체
  //   변경 전: DrivingDataSource _dataSource = MockObdDataSource(scenario: _selectedScenario);
  //   변경 후: DrivingDataSource _dataSource = RealObdDataSource(ObdDatasource.connected!);
  DrivingDataSource? _dataSource;
  StreamSubscription<DrivingSample>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadVinStatus();
  }

  /// SharedPreferences에서 VIN 인증 상태 로드
  /// VIN 인증 성공 조건: auth_token이 비어 있지 않고 vin이 존재
  Future<void> _loadVinStatus() async {
    final prefs     = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final vin       = prefs.getString('vin')        ?? '';
    final carModel  = prefs.getString('car_model')  ?? '';

    setState(() {
      _vin           = vin;
      _carModel      = carModel;
      _isVinVerified = authToken.isNotEmpty && vin.isNotEmpty;
    });
  }

  // ── 주행 시작 ─────────────────────────────────────────────────────────────
  void _startDriving() {
    if (!_isVinVerified) return;

    _dataSource = MockObdDataSource(scenario: _selectedScenario);
    _scoreEngine.reset();
    _startTime = DateTime.now();

    setState(() {
      _isDriving     = true;
      _currentSample = null;
      _prevSample    = null;
      _recentEvents.clear();
    });

    _subscription = _dataSource!.watchDrivingData(_vin).listen((sample) {
      if (!mounted) return;
      final newEvents = _scoreEngine.processSample(sample, _prevSample);
      setState(() {
        _prevSample    = _currentSample;
        _currentSample = sample;
        if (newEvents.isNotEmpty) {
          _recentEvents.insertAll(0, newEvents);
          if (_recentEvents.length > 30) {
            _recentEvents.removeRange(30, _recentEvents.length);
          }
        }
      });
    });
  }

  // ── 주행 종료 ─────────────────────────────────────────────────────────────
  Future<void> _stopDriving() async {
    await _subscription?.cancel();
    _subscription = null;
    _dataSource?.dispose();
    _dataSource = null;

    final endTime = DateTime.now();
    final result  = _scoreEngine.buildResult();
    setState(() => _isDriving = false);

    // DB 저장 (실패해도 결과 화면은 정상 표시)
    try {
      await TripSessionRepository.instance.saveScoreResult(
        result:    result,
        vin:       _vin,
        startTime: _startTime ?? endTime,
        endTime:   endTime,
        sampleCount: _currentSample != null ? 1 : 0, // 추후 누적 카운터로 교체
      );
    } catch (_) {}

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrivingScoreResultScreen(
          result:    result,
          startTime: _startTime,
          endTime:   endTime,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dataSource?.dispose();
    super.dispose();
  }

  // ── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('안전점수 모니터', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1B3A5C),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _isDriving ? null : _loadVinStatus,
            tooltip: 'VIN 상태 새로고침',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // VIN 인증 상태 카드
            _VinStatusCard(
              vin:        _vin,
              carModel:   _carModel,
              isVerified: _isVinVerified,
            ),
            const SizedBox(height: 16),

            // 미인증 안내 메시지
            if (!_isVinVerified && !_isDriving) ...[
              _UnverifiedBanner(),
              const SizedBox(height: 12),
            ],

            // 현재 안전점수
            _ScoreGaugeCard(
              score:     _scoreEngine.score,
              isDriving: _isDriving,
            ),
            const SizedBox(height: 16),

            // 센서 데이터 4개
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
                  value: _currentSample != null ? '${_currentSample!.speed.toInt()}' : '--',
                  unit: 'km/h',
                  icon: Icons.speed_rounded,
                  color: const Color(0xFF2563EB),
                ),
                _SensorCard(
                  label: 'RPM',
                  value: _currentSample != null ? '${_currentSample!.rpm.toInt()}' : '--',
                  unit: 'rpm',
                  icon: Icons.rotate_right_rounded,
                  color: const Color(0xFF1D9E75),
                ),
                _SensorCard(
                  label: '스로틀',
                  value: _currentSample != null ? '${_currentSample!.throttle.toInt()}' : '--',
                  unit: '%',
                  icon: Icons.tune_rounded,
                  color: const Color(0xFFEF9F27),
                ),
                _SensorCard(
                  label: '엔진 부하',
                  value: _currentSample != null ? '${_currentSample!.engineLoad.toInt()}' : '--',
                  unit: '%',
                  icon: Icons.memory_rounded,
                  color: const Color(0xFFD85A30),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Mock 시나리오 선택 (주행 중 또는 실제 OBD 연결 시 숨김)
            // TODO: 실제 RealObdDataSource 사용 시 이 블록 전체 제거 또는 조건 추가
            if (!_isDriving) ...[
              _ScenarioSelector(
                selected: _selectedScenario,
                onChanged: (s) => setState(() => _selectedScenario = s),
              ),
              const SizedBox(height: 12),
            ],

            // 주행 시작/종료 버튼
            _DriveControlButton(
              isDriving:     _isDriving,
              isVinVerified: _isVinVerified,
              onStart:       _startDriving,
              onStop:        _stopDriving,
            ),
            const SizedBox(height: 16),

            // 감점 이벤트 목록
            if (_recentEvents.isNotEmpty) ...[
              const Text(
                '감점 이벤트',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1B3A5C),
                ),
              ),
              const SizedBox(height: 8),
              ..._recentEvents.take(15).map((e) => _EventTile(event: e)),
            ],
            if (_isDriving && _recentEvents.isEmpty) const _EmptyEventHint(),
          ],
        ),
      ),
    );
  }
}

// ── VIN 인증 상태 카드 ──────────────────────────────────────────────────────────
class _VinStatusCard extends StatelessWidget {
  final String vin;
  final String carModel;
  final bool isVerified;

  const _VinStatusCard({required this.vin, required this.carModel, required this.isVerified});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isVerified ? const Color(0xFF1D9E75) : Colors.orange,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: isVerified ? const Color(0xFFE1F5EE) : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isVerified ? Icons.verified_rounded : Icons.warning_rounded,
                color: isVerified ? const Color(0xFF1D9E75) : Colors.orange,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isVerified ? 'VIN 인증 완료' : 'VIN 인증 필요',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isVerified ? const Color(0xFF1D9E75) : Colors.orange,
                    ),
                  ),
                  if (isVerified && vin.isNotEmpty)
                    Text(
                      '${carModel.isNotEmpty ? '$carModel · ' : ''}$vin',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    const Text(
                      '온보딩에서 차량 인증을 완료해주세요',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── 미인증 안내 배너 ─────────────────────────────────────────────────────────────
class _UnverifiedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: Colors.orange.shade700, size: 18),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '차량 VIN 인증 후 주행 점수를 측정할 수 있습니다.',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
          ],
        ),
      );
}

// ── 점수 게이지 카드 ─────────────────────────────────────────────────────────────
class _ScoreGaugeCard extends StatelessWidget {
  final int score;
  final bool isDriving;
  const _ScoreGaugeCard({required this.score, required this.isDriving});

  Color get _scoreColor {
    if (score >= 90) return const Color(0xFF1D9E75);
    if (score >= 70) return const Color(0xFFEF9F27);
    return const Color(0xFFE53E3E);
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: isDriving ? const Color(0xFF1D9E75) : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isDriving ? '주행 중 · 실시간 측정' : '주행 대기',
                  style: TextStyle(fontSize: 12, color: isDriving ? const Color(0xFF1D9E75) : Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              isDriving ? '$score' : '--',
              style: TextStyle(
                fontSize: 72, fontWeight: FontWeight.bold,
                color: isDriving ? _scoreColor : Colors.grey[300], height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text('안전점수', style: TextStyle(fontSize: 13, color: Colors.grey[500])),
            if (isDriving && score < 100) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _scoreColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '총 ${100 - score}점 감점',
                  style: TextStyle(fontSize: 12, color: _scoreColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      );
}

// ── 센서 카드 ────────────────────────────────────────────────────────────────────
class _SensorCard extends StatelessWidget {
  final String label, value, unit;
  final IconData icon;
  final Color color;
  const _SensorCard({
    required this.label, required this.value, required this.unit,
    required this.icon, required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ),
            ]),
          ],
        ),
      );
}

// ── Mock 시나리오 선택 ───────────────────────────────────────────────────────────
// TODO: 실제 RealObdDataSource 전환 시 이 위젯을 제거하거나 'Mock 모드에서만 표시' 조건 추가
class _ScenarioSelector extends StatelessWidget {
  final MockDriveScenario selected;
  final ValueChanged<MockDriveScenario> onChanged;
  const _ScenarioSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEDFB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.science_rounded, size: 16, color: Color(0xFF7F77DD)),
            ),
            const SizedBox(width: 12),
            const Text('Mock 시나리오', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1B3A5C))),
            const Spacer(),
            DropdownButton<MockDriveScenario>(
              value: selected,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 12, color: Color(0xFF1B3A5C)),
              items: MockDriveScenario.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (s) { if (s != null) onChanged(s); },
            ),
          ],
        ),
      );
}

// ── 주행 시작/종료 버튼 ──────────────────────────────────────────────────────────
class _DriveControlButton extends StatelessWidget {
  final bool isDriving, isVinVerified;
  final VoidCallback onStart;
  final Future<void> Function() onStop;
  const _DriveControlButton({
    required this.isDriving, required this.isVinVerified,
    required this.onStart, required this.onStop,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 54,
        child: isDriving
            ? ElevatedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_rounded, color: Colors.white),
                label: const Text('주행 종료  →  최종 결과 보기',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE53E3E),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              )
            : ElevatedButton.icon(
                onPressed: isVinVerified ? onStart : null,
                icon: const Icon(Icons.play_circle_rounded, color: Colors.white),
                label: Text(
                  isVinVerified ? '주행 시작' : 'VIN 인증 후 이용 가능',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B3A5C),
                  disabledBackgroundColor: Colors.grey[300],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
      );
}

// ── 이벤트 타일 ──────────────────────────────────────────────────────────────────
class _EventTile extends StatelessWidget {
  final DriveEvent event;
  const _EventTile({required this.event});

  IconData get _icon {
    switch (event.type) {
      case EventType.harshAccel:     return Icons.arrow_upward_rounded;
      case EventType.harshBrake:     return Icons.arrow_downward_rounded;
      case EventType.hardStart:      return Icons.directions_car_rounded;
      case EventType.highRpm:        return Icons.speed_rounded;
      case EventType.throttleSpike:  return Icons.tune_rounded;
      case EventType.idling:         return Icons.timer_rounded;
      case EventType.engineOverload: return Icons.local_fire_department_rounded;
      default:                       return Icons.warning_amber_rounded;
    }
  }

  Color get _color {
    switch (event.penalty) {
      case 2: return const Color(0xFFEF9F27);
      case 3: return const Color(0xFFE67E22);
      case 4: return const Color(0xFFE53E3E);
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = event.timestamp;
    final time = '${ts.hour.toString().padLeft(2, '0')}:'
        '${ts.minute.toString().padLeft(2, '0')}:'
        '${ts.second.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(_icon, size: 16, color: _color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title.isNotEmpty ? event.title : event.type.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF1B3A5C))),
                if (event.description.isNotEmpty)
                  Text(event.description, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('-${event.penalty}점', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _color)),
              Text(time, style: TextStyle(fontSize: 10, color: Colors.grey[400])),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyEventHint extends StatelessWidget {
  const _EmptyEventHint();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Column(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 36, color: Colors.green[300]),
            const SizedBox(height: 8),
            const Text('감점 이벤트 없음\n안전 운전 중입니다',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      );
}
