import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/enums/obd_connection_mode.dart';
import '../../core/utils/app_mode_controller.dart';
import '../../data/datasources/driving_data_source.dart';
import '../../data/datasources/dry_run_obd_data_source.dart';
import '../../data/models/driving_sample.dart';
import '../../data/models/drive_event.dart';
import '../../data/models/score_result.dart';
import '../../core/utils/scoring_utils.dart';
import '../../core/utils/drive_tracking_state_machine.dart';
import '../../data/repositories/trip_session_repository.dart';
import 'driving_score_result_screen.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

class DrivingScoreScreen extends StatefulWidget {
  const DrivingScoreScreen({super.key});

  @override
  State<DrivingScoreScreen> createState() => _DrivingScoreScreenState();
}

class _DrivingScoreScreenState extends State<DrivingScoreScreen> {
  // ── VIN 인증 상태 ─────────────────────────────────────────────────────────
  String _vin       = '';
  String _carModel  = '';
  bool   _isVinVerified = false;

  // ── 주행 추적 상태 머신 ──────────────────────────────────────────────────
  final DriveTrackingStateMachine _stateMachine = DriveTrackingStateMachine();
  DriveTrackingState _trackingState = DriveTrackingState.idle;

  // ── 모니터링 / 세션 상태 ─────────────────────────────────────────────────
  bool _isMonitoring = false; // OBD 스트림 수신 중
  bool _isTripActive = false; // 점수 측정 세션 활성 (driving 상태)
  bool _isEndingTrip = false; // 세션 종료 처리 중 (중복 방지)

  DrivingSample? _currentSample;
  DrivingSample? _prevSample;
  DateTime?      _tripStartTime;
  final List<DriveEvent> _recentEvents = [];
  final DrivingScoreEngine _scoreEngine = DrivingScoreEngine();

  // ── Mock 시나리오 ─────────────────────────────────────────────────────────
  // TODO: 실제 RealObdDataSource 전환 시 이 변수와 드롭다운 UI를 제거할 것
  MockDriveScenario _selectedScenario = MockDriveScenario.risky;

  // ── 데이터 소스 ───────────────────────────────────────────────────────────
  // TODO: 실제 ELM327 연결 시 RealObdDataSource로 교체
  DrivingDataSource?         _dataSource;
  StreamSubscription<DrivingSample>? _subscription;

  @override
  void initState() {
    super.initState();
    _loadVinStatus();
  }

  Future<void> _loadVinStatus() async {
    final prefs     = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final vin       = prefs.getString('vin')        ?? '';
    final carModel  = prefs.getString('car_model')  ?? '';
    setState(() {
      _vin          = vin;
      _carModel     = carModel;
      _isVinVerified = authToken.isNotEmpty && vin.isNotEmpty;
    });
  }

  // ── 모니터링 시작 ─────────────────────────────────────────────────────────
  /// OBD 스트림을 구독하고 상태 머신을 시작한다.
  /// 실제 ELM327 연결 시에는 연결 직후 자동으로 호출될 수 있다.
  void _startMonitoring() {
    if (_isMonitoring || !_isVinVerified) return;

    // AppModeController 모드에 따라 데이터 소스 선택
    // 기본: mock / dryRun → 실제 차량에 명령 전송하지 않음
    // real: RealObdDataSource (TODO: 실제 연결 구현 후 교체)
    final appMode = AppModeController().mode;
    if (appMode == ObdConnectionMode.dryRun) {
      _dataSource = DryRunObdDataSource();
    } else {
      // mock 또는 real (real은 현재 MockObdDataSource로 fallback — TODO 교체)
      _dataSource = MockObdDataSource(scenario: _selectedScenario);
    }
    _stateMachine.reset();
    _scoreEngine.reset();

    setState(() {
      _isMonitoring  = true;
      _isTripActive  = false;
      _trackingState = DriveTrackingState.idle;
      _currentSample = null;
      _prevSample    = null;
      _recentEvents.clear();
    });

    _subscription = _dataSource!.watchDrivingData(_vin).listen(_onSample);
  }

  // ── 모니터링 중지 (수동) ──────────────────────────────────────────────────
  Future<void> _stopMonitoring() async {
    if (_isTripActive) {
      // 세션 활성 중이면 세션도 함께 종료
      await _endTrip();
    }
    await _subscription?.cancel();
    _subscription = null;
    _dataSource?.dispose();
    _dataSource = null;

    if (mounted) {
      setState(() {
        _isMonitoring  = false;
        _isTripActive  = false;
        _trackingState = DriveTrackingState.idle;
      });
    }
  }

  // ── 샘플 수신 → 상태 머신 처리 ───────────────────────────────────────────
  void _onSample(DrivingSample sample) {
    if (!mounted) return;

    final transition = _stateMachine.process(
      sample,
      isObdConnected: true, // TODO: 실제 연결 시 BLE 연결 상태 전달
    );

    // 상태 전이 처리
    if (transition != null) {
      _handleTransition(transition, sample);
    }

    // 현재 상태에 맞는 점수 계산 (세션 활성 or 공회전 감지 구간)
    final shouldScore = _isTripActive ||
        _trackingState == DriveTrackingState.engineOn ||
        _trackingState == DriveTrackingState.stopped;

    if (shouldScore) {
      final newEvents = _scoreEngine.processSample(
        sample,
        _prevSample,
        trackingState: _stateMachine.state,
      );
      setState(() {
        _prevSample    = _currentSample;
        _currentSample = sample;
        _trackingState = _stateMachine.state;
        if (newEvents.isNotEmpty) {
          _recentEvents.insertAll(0, newEvents);
          if (_recentEvents.length > 30) {
            _recentEvents.removeRange(30, _recentEvents.length);
          }
        }
      });
    } else {
      setState(() {
        _prevSample    = _currentSample;
        _currentSample = sample;
        _trackingState = _stateMachine.state;
      });
    }
  }

  // ── 상태 전이 이벤트 처리 ─────────────────────────────────────────────────
  void _handleTransition(DriveTrackingState next, DrivingSample sample) {
    switch (next) {
      case DriveTrackingState.driving:
        if (!_isTripActive) {
          // 최초 driving 진입 → 세션 시작
          _scoreEngine.reset();
          _tripStartTime = DateTime.now();
          setState(() => _isTripActive = true);
        }
        break;

      case DriveTrackingState.tripEnded:
        if (_isTripActive && !_isEndingTrip) {
          _endTrip(); // 자동 세션 종료
        }
        break;

      case DriveTrackingState.stopped:
        // 세션 유지, 공회전 카운터는 scoring_utils가 관리
        break;

      case DriveTrackingState.engineOn:
      case DriveTrackingState.idle:
        break;
    }
  }

  // ── 세션 종료 (자동 or 수동) ──────────────────────────────────────────────
  Future<void> _endTrip() async {
    if (_isEndingTrip) return;
    setState(() => _isEndingTrip = true);

    await _subscription?.cancel();
    _subscription = null;
    _dataSource?.dispose();
    _dataSource = null;

    final endTime = DateTime.now();
    final result  = _scoreEngine.buildResult();

    setState(() {
      _isMonitoring  = false;
      _isTripActive  = false;
      _isEndingTrip  = false;
      _trackingState = DriveTrackingState.idle;
    });

    // DB 저장 (실패해도 결과 화면은 정상 표시)
    try {
      await TripSessionRepository.instance.saveScoreResult(
        result:    result,
        vin:       _vin,
        startTime: _tripStartTime ?? endTime,
        endTime:   endTime,
      );
    } catch (_) {}

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DrivingScoreResultScreen(
          result:    result,
          startTime: _tripStartTime,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('안전점수 모니터', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.textSecondary),
            onPressed: _isMonitoring ? null : _loadVinStatus,
            tooltip: 'VIN 상태 새로고침',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // VIN 인증 상태 카드
            _VinStatusCard(vin: _vin, carModel: _carModel, isVerified: _isVinVerified),
            const SizedBox(height: 10),

            // 미인증 안내
            if (!_isVinVerified) ...[
              _UnverifiedBanner(),
              const SizedBox(height: 10),
            ],

            // 주행 추적 상태 배지
            if (_isMonitoring) ...[
              _TrackingStateBadge(state: _trackingState),
              const SizedBox(height: 10),
            ],

            // 현재 안전점수
            _ScoreGaugeCard(score: _scoreEngine.score, isTripActive: _isTripActive),
            const SizedBox(height: 12),

            // 센서 데이터 4개
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.5,
              children: [
                _SensorCard(
                  label: '속도',
                  value: _currentSample != null ? '${_currentSample!.speed.toInt()}' : '--',
                  unit: 'km/h',
                  icon: Icons.speed_rounded,
                  color: AppColors.primary,
                ),
                _SensorCard(
                  label: 'RPM',
                  value: _currentSample != null ? '${_currentSample!.rpm.toInt()}' : '--',
                  unit: 'rpm',
                  icon: Icons.rotate_right_rounded,
                  color: AppColors.success,
                ),
                _SensorCard(
                  label: '스로틀',
                  value: _currentSample != null ? '${_currentSample!.throttle.toInt()}' : '--',
                  unit: '%',
                  icon: Icons.tune_rounded,
                  color: AppColors.warning,
                ),
                _SensorCard(
                  label: '엔진 부하',
                  value: _currentSample != null ? '${_currentSample!.engineLoad.toInt()}' : '--',
                  unit: '%',
                  icon: Icons.memory_rounded,
                  color: AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Mock 시나리오 선택 (모니터링 전에만 표시)
            // TODO: 실제 RealObdDataSource 전환 시 제거
            if (!_isMonitoring) ...[
              _ScenarioSelector(
                selected: _selectedScenario,
                onChanged: (s) => setState(() => _selectedScenario = s),
              ),
              const SizedBox(height: 10),
            ],

            // 모니터링 시작/중지 버튼
            _MonitoringButton(
              isMonitoring:  _isMonitoring,
              isTripActive:  _isTripActive,
              isVinVerified: _isVinVerified,
              onStart:       _startMonitoring,
              onStop:        _stopMonitoring,
            ),
            const SizedBox(height: 14),

            // 감점 이벤트 목록
            if (_recentEvents.isNotEmpty) ...[
              const Text('감점 이벤트', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              ..._recentEvents.take(15).map((e) => _EventTile(event: e)),
            ],
            if (_isTripActive && _recentEvents.isEmpty) const _EmptyEventHint(),
          ],
        ),
      ),
    );
  }
}

// ── 주행 추적 상태 배지 ───────────────────────────────────────────────────────
class _TrackingStateBadge extends StatelessWidget {
  final DriveTrackingState state;
  const _TrackingStateBadge({required this.state});

  Color get _color {
    switch (state) {
      case DriveTrackingState.idle:      return AppColors.textSecondary;
      case DriveTrackingState.engineOn:  return AppColors.warning;
      case DriveTrackingState.driving:   return AppColors.success;
      case DriveTrackingState.stopped:   return AppColors.primary;
      case DriveTrackingState.tripEnded: return AppColors.danger;
    }
  }

  IconData get _icon {
    switch (state) {
      case DriveTrackingState.idle:      return Icons.radio_button_unchecked;
      case DriveTrackingState.engineOn:  return Icons.key_rounded;
      case DriveTrackingState.driving:   return Icons.directions_car_rounded;
      case DriveTrackingState.stopped:   return Icons.pause_circle_rounded;
      case DriveTrackingState.tripEnded: return Icons.flag_rounded;
    }
  }

  String get _description {
    switch (state) {
      case DriveTrackingState.idle:      return 'OBD 신호 대기 중';
      case DriveTrackingState.engineOn:  return '시동 감지 · 출발 대기 (5km/h 이상 3초 유지 시 측정 시작)';
      case DriveTrackingState.driving:   return '안전점수 실시간 측정 중';
      case DriveTrackingState.stopped:   return '정차 중 · 세션 유지 (5분 초과 또는 시동 꺼지면 종료)';
      case DriveTrackingState.tripEnded: return '주행 세션 종료';
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(_icon, size: 16, color: _color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _color),
                  ),
                  Text(
                    _description,
                    style: AppTextStyles.captionHint,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── VIN 인증 상태 카드 ────────────────────────────────────────────────────────
class _VinStatusCard extends StatelessWidget {
  final String vin;
  final String carModel;
  final bool isVerified;
  const _VinStatusCard({required this.vin, required this.carModel, required this.isVerified});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isVerified ? AppColors.success.withValues(alpha: 0.4) : AppColors.warning.withValues(alpha: 0.4),
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: isVerified ? AppColors.successLight : AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isVerified ? Icons.verified_rounded : Icons.warning_rounded,
                color: isVerified ? AppColors.success : AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isVerified ? 'VIN 인증 완료' : 'VIN 인증 필요',
                    style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14,
                      color: isVerified ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  if (isVerified && vin.isNotEmpty)
                    Text(
                      '${carModel.isNotEmpty ? '$carModel · ' : ''}$vin',
                      style: AppTextStyles.captionHint,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    const Text(
                      '온보딩에서 차량 인증을 완료해주세요',
                      style: AppTextStyles.captionHint,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ── 미인증 안내 배너 ──────────────────────────────────────────────────────────
class _UnverifiedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '차량 VIN 인증 후 주행 점수를 측정할 수 있습니다.',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
}

// ── 점수 게이지 카드 ──────────────────────────────────────────────────────────
class _ScoreGaugeCard extends StatelessWidget {
  final int score;
  final bool isTripActive;
  const _ScoreGaugeCard({required this.score, required this.isTripActive});

  Color get _scoreColor {
    if (score >= 90) return AppColors.success;
    if (score >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: isTripActive ? AppColors.success : AppColors.border,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isTripActive ? '주행 중 · 실시간 측정' : '주행 대기',
                  style: TextStyle(
                    fontSize: 12,
                    color: isTripActive ? AppColors.success : AppColors.textHint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              isTripActive ? '$score' : '--',
              style: TextStyle(
                fontSize: 64, fontWeight: FontWeight.w700,
                color: isTripActive ? _scoreColor : AppColors.border, height: 1,
              ),
            ),
            const SizedBox(height: 4),
            const Text('안전점수', style: AppTextStyles.captionHint),
            if (isTripActive && score < 100) ...[
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

// ── 센서 카드 ─────────────────────────────────────────────────────────────────
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
            Row(children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(label, style: AppTextStyles.caption),
            ]),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit, style: AppTextStyles.captionHint),
              ),
            ]),
          ],
        ),
      );
}

// ── Mock 시나리오 선택 ────────────────────────────────────────────────────────
// TODO: 실제 RealObdDataSource 전환 시 제거
class _ScenarioSelector extends StatelessWidget {
  final MockDriveScenario selected;
  final ValueChanged<MockDriveScenario> onChanged;
  const _ScenarioSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE9FE),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.science_rounded, size: 15, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(width: 10),
            const Text('Mock 시나리오', style: AppTextStyles.label),
            const Spacer(),
            DropdownButton<MockDriveScenario>(
              value: selected,
              underline: const SizedBox(),
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              items: MockDriveScenario.values
                  .map((s) => DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (s) { if (s != null) onChanged(s); },
            ),
          ],
        ),
      );
}

// ── 모니터링 시작/중지 버튼 ───────────────────────────────────────────────────
class _MonitoringButton extends StatelessWidget {
  final bool isMonitoring, isTripActive, isVinVerified;
  final VoidCallback onStart;
  final Future<void> Function() onStop;

  const _MonitoringButton({
    required this.isMonitoring, required this.isTripActive,
    required this.isVinVerified, required this.onStart, required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    if (isMonitoring) {
      return Column(
        children: [
          // 세션 활성 중이면 "지금 종료" 버튼 표시
          if (isTripActive)
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_rounded, color: Colors.white, size: 18),
                label: const Text('지금 종료  →  결과 보기',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          if (isTripActive) const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.sensors_off_rounded, size: 16),
              label: const Text('모니터링 중지', style: TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: const BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: isVinVerified ? onStart : null,
        icon: const Icon(Icons.sensors_rounded, color: Colors.white, size: 18),
        label: Text(
          isVinVerified ? '모니터링 시작 (자동 주행 감지)' : 'VIN 인증 후 이용 가능',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.border,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

// ── 이벤트 타일 ───────────────────────────────────────────────────────────────
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
      case 2: return AppColors.warning;
      case 3: return const Color(0xFFEA580C);
      case 4: return AppColors.danger;
      default: return AppColors.textSecondary;
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _color.withValues(alpha: 0.25)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(7)),
            child: Icon(_icon, size: 15, color: _color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title.isNotEmpty ? event.title : event.type.name,
                    style: AppTextStyles.label),
                if (event.description.isNotEmpty)
                  Text(event.description, style: AppTextStyles.captionHint),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('-${event.penalty}점', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: _color)),
              Text(time, style: AppTextStyles.captionHint),
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
        child: const Column(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 32, color: AppColors.success),
            SizedBox(height: 8),
            Text('감점 이벤트 없음\n안전 운전 중입니다',
                textAlign: TextAlign.center, style: AppTextStyles.bodySecondary),
          ],
        ),
      );
}
