import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/dry_run_obd_data_source.dart';
import '../../data/datasources/obd_datasource.dart';
import '../../data/datasources/real_read_only_data_source.dart';
import '../../data/models/drive_event.dart';
import '../../data/models/driving_sample.dart';
import '../../data/models/obd_drive_log.dart';
import '../../data/models/score_result.dart';
import '../../core/utils/scoring_utils.dart';
import '../../core/utils/drive_tracking_state_machine.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

// ── 주행 단계 ──────────────────────────────────────────────────────────────────
enum _DrivePhase {
  bleCheck,
  step1DryRun,
  step2ManualPid,
  step3Stationary,
  step4Checklist,
  recording,
  autoStopped,
  report,
}

// ── 수동 PID 테스트 대상 (Step 2) ─────────────────────────────────────────────
const _testPids = [
  _PidInfo('010C', 'RPM'),
  _PidInfo('010D', '속도'),
  _PidInfo('0111', '스로틀'),
  _PidInfo('0104', '엔진 부하'),
];

class _PidInfo {
  final String pid;
  final String label;
  const _PidInfo(this.pid, this.label);
}

// ── 체크리스트 항목 (Step 4) ──────────────────────────────────────────────────
const _checklistItems = [
  '차량 경고등 이상 없음을 육안으로 확인',
  'P단 정차 상태 확인',
  'Dry-run 위험 명령 차단 테스트 완료 (Step 1)',
  '조향각 · 방향지시등 · Raw CAN 기능 제거 확인',
  '주행 중 앱을 조작하지 않겠음',
  '동승자가 영상 촬영 또는 기록 예정',
  '이상 발생 시 즉시 정차하겠음',
];

// ─────────────────────────────────────────────────────────────────────────────

class RealDriveScreen extends StatefulWidget {
  const RealDriveScreen({super.key});

  @override
  State<RealDriveScreen> createState() => _RealDriveScreenState();
}

class _RealDriveScreenState extends State<RealDriveScreen> {
  // ── 기본 상태 ─────────────────────────────────────────────────────────────
  _DrivePhase _phase = _DrivePhase.bleCheck;
  String _vin       = '';
  String _carModel  = '';

  // ── Step 1: Dry-run 차단 테스트 ──────────────────────────────────────────
  bool                    _step1Running = false;
  List<BlockTestResult>?  _blockResults;

  // ── Step 2: 수동 PID 테스트 ──────────────────────────────────────────────
  bool                         _step2Running = false;
  final Map<String, ObdDriveLog> _pidResults = {};

  // ── Step 3: 정차 폴링 테스트 ──────────────────────────────────────────────
  bool                  _step3Running  = false;
  int                   _step3Progress = 0;
  static const          _step3Total    = 5;
  StationaryTestResult? _step3Result;

  // ── Step 4: 체크리스트 ────────────────────────────────────────────────────
  late List<bool> _checks;

  // ── 주행 기록 ─────────────────────────────────────────────────────────────
  RealReadOnlyDataSource?        _dataSource;
  StreamSubscription<dynamic>?   _subscription;
  DrivingSample?                 _currentSample;
  DrivingSample?                 _prevSample;
  final DrivingScoreEngine       _scoreEngine   = DrivingScoreEngine();
  final DriveTrackingStateMachine _stateMachine = DriveTrackingStateMachine();
  DriveTrackingState             _trackingState = DriveTrackingState.idle;
  bool                           _isTripActive  = false;
  DateTime?                      _tripStartTime;
  final List<DriveEvent>         _recentEvents  = [];
  bool                           _isFinishing   = false;
  DateTime?                      _tripEndTime;
  ScoreResult?                   _finalResult;

  @override
  void initState() {
    super.initState();
    _checks = List.filled(_checklistItems.length, false);
    _loadVin();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkBle());
  }

  Future<void> _loadVin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vin      = prefs.getString('vin')        ?? '';
      _carModel = prefs.getString('car_model')  ?? '';
    });
  }

  void _checkBle() {
    final connected = ObdDatasource.connected != null;
    if (connected) {
      setState(() => _phase = _DrivePhase.step1DryRun);
    } else {
      setState(() => _phase = _DrivePhase.bleCheck);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _dataSource?.dispose();
    super.dispose();
  }

  // ── Step 1: Dry-run 차단 테스트 ──────────────────────────────────────────
  Future<void> _runStep1() async {
    setState(() { _step1Running = true; _blockResults = null; });
    await Future.delayed(const Duration(milliseconds: 80));
    final results = DryRunObdDataSource().runBlockTests();
    if (mounted) {
      setState(() {
        _blockResults  = results;
        _step1Running  = false;
      });
    }
  }

  bool get _step1Passed =>
      _blockResults != null && _blockResults!.every((r) => r.blocked);

  // ── Step 2: 수동 PID 테스트 ──────────────────────────────────────────────
  Future<void> _testPid(String pid) async {
    final src = ObdDatasource.connected;
    if (src == null) {
      _showSnack('BLE 연결이 끊겼습니다. 다시 연결해주세요.');
      return;
    }
    setState(() { _step2Running = true; _pidResults.remove(pid); });
    final ds  = RealReadOnlyDataSource(obd: src);
    final log = await ds.testSinglePid(pid);
    if (mounted) {
      setState(() {
        _pidResults[pid] = log;
        _step2Running    = false;
      });
    }
  }

  bool get _step2Passed =>
      _testPids.every((p) {
        final r = _pidResults[p.pid];
        return r != null && !r.isError && !r.isBlocked;
      });

  // ── Step 3: 정차 폴링 테스트 ─────────────────────────────────────────────
  Future<void> _runStep3() async {
    final src = ObdDatasource.connected;
    if (src == null) { _showSnack('BLE 연결이 끊겼습니다.'); return; }

    setState(() { _step3Running = true; _step3Progress = 0; _step3Result = null; });
    final ds = RealReadOnlyDataSource(obd: src);
    final result = await ds.runStationaryTest(
      sampleCount:    _step3Total,
      sampleInterval: const Duration(seconds: 2),
      onProgress: (done, total) {
        if (mounted) setState(() => _step3Progress = done);
      },
    );
    if (mounted) {
      setState(() { _step3Result = result; _step3Running = false; });
    }
  }

  bool get _step3Passed => _step3Result?.passed == true;

  // ── 체크리스트 ────────────────────────────────────────────────────────────
  bool get _allChecked => _checks.every((c) => c);

  // ── 주행 기록 시작 ────────────────────────────────────────────────────────
  Future<void> _startRecording() async {
    final src = ObdDatasource.connected;
    if (src == null || _vin.isEmpty) {
      _showSnack('BLE 연결 또는 VIN 인증이 필요합니다.');
      return;
    }

    _dataSource = RealReadOnlyDataSource(obd: src,
        interPidDelay: const Duration(milliseconds: 500));
    _scoreEngine.reset();
    _stateMachine.reset();
    _tripStartTime = DateTime.now();
    _isTripActive  = false;
    _recentEvents.clear();

    setState(() => _phase = _DrivePhase.recording);

    _subscription = _dataSource!.watchDrivingData(_vin).listen(
      _onSample,
      onDone: _onStreamDone,
      onError: (e) {},
    );
  }

  void _onSample(DrivingSample sample) {
    if (!mounted) return;

    final transition = _stateMachine.process(sample, isObdConnected: true);
    if (transition != null) _handleTransition(transition);

    final shouldScore = _isTripActive ||
        _trackingState == DriveTrackingState.engineOn ||
        _trackingState == DriveTrackingState.stopped;

    if (shouldScore) {
      final newEvents = _scoreEngine.processSample(sample, _prevSample,
          trackingState: _stateMachine.state);
      setState(() {
        _prevSample    = _currentSample;
        _currentSample = sample;
        _trackingState = _stateMachine.state;
        if (newEvents.isNotEmpty) {
          _recentEvents.insertAll(0, newEvents);
          if (_recentEvents.length > 20) {
            _recentEvents.removeRange(20, _recentEvents.length);
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

  void _handleTransition(DriveTrackingState next) {
    if (next == DriveTrackingState.driving && !_isTripActive) {
      _scoreEngine.reset();
      _tripStartTime = DateTime.now();
      setState(() => _isTripActive = true);
    }
  }

  void _onStreamDone() {
    // 자동 중단인 경우 (사용자 중단이 아닌 에러로 인한 종료)
    final reason = _dataSource?.stopReason;
    if (mounted && reason != null && reason != '사용자가 중단') {
      setState(() => _phase = _DrivePhase.autoStopped);
    }
  }

  Future<void> _stopRecording() async {
    if (_isFinishing) return;
    _isFinishing = true;
    await _subscription?.cancel();
    _subscription   = null;
    _dataSource?.dispose();
    _tripEndTime  = DateTime.now();
    _finalResult  = _scoreEngine.buildResult();
    if (mounted) setState(() { _phase = _DrivePhase.report; _isFinishing = false; });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('실차 주행 안전 테스트', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: _phase == _DrivePhase.recording ||
                _phase == _DrivePhase.autoStopped ||
                _phase == _DrivePhase.report
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: _buildStepBar(),
              ),
      ),
      body: _buildBody(),
    );
  }

  // ── 상단 단계 표시 바 ─────────────────────────────────────────────────────
  Widget _buildStepBar() {
    final steps = ['Dry-run 검증', 'PID 테스트', '정차 폴링', '체크리스트'];
    final phaseIndex = switch (_phase) {
      _DrivePhase.step1DryRun    => 0,
      _DrivePhase.step2ManualPid => 1,
      _DrivePhase.step3Stationary => 2,
      _DrivePhase.step4Checklist => 3,
      _         => -1,
    };
    if (phaseIndex < 0) return const SizedBox.shrink();

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: steps.asMap().entries.map((e) {
          final i       = e.key;
          final label   = e.value;
          final done    = i < phaseIndex;
          final current = i == phaseIndex;
          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: done
                        ? AppColors.success
                        : current
                            ? AppColors.primary
                            : AppColors.border,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: current ? Colors.white : AppColors.textHint,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      color: current ? AppColors.primary : AppColors.textHint,
                      fontWeight: current ? FontWeight.w700 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (i < steps.length - 1)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.chevron_right, size: 12, color: AppColors.border),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBody() {
    return switch (_phase) {
      _DrivePhase.bleCheck        => _buildBleCheckView(),
      _DrivePhase.step1DryRun     => _buildStep1View(),
      _DrivePhase.step2ManualPid  => _buildStep2View(),
      _DrivePhase.step3Stationary => _buildStep3View(),
      _DrivePhase.step4Checklist  => _buildStep4View(),
      _DrivePhase.recording       => _buildRecordingView(),
      _DrivePhase.autoStopped     => _buildAutoStoppedView(),
      _DrivePhase.report          => _buildReportView(),
    };
  }

  // ── BLE 미연결 화면 ───────────────────────────────────────────────────────
  Widget _buildBleCheckView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: const BoxDecoration(
              color: AppColors.warningLight, shape: BoxShape.circle),
            child: const Icon(Icons.bluetooth_disabled,
                size: 32, color: AppColors.warning),
          ),
          const SizedBox(height: 16),
          const Text('BLE 스캐너 미연결', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          const Text(
            'ELM327 BLE 스캐너가 연결되어 있어야 실차 주행 테스트를 진행할 수 있습니다.\n'
            '홈 화면 또는 연결 화면에서 스캐너를 먼저 연결해주세요.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('홈으로',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Step 1: Dry-run 위험 명령 차단 테스트 ───────────────────────────────
  Widget _buildStep1View() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhaseHeader(
          '1단계: Dry-run 위험 명령 차단 테스트',
          '실제 차량에 명령을 보내기 전 SafeObdCommandValidator가 위험 명령을 100% 차단하는지 확인합니다.',
        ),
        const SizedBox(height: 16),

        // 안내
        _buildInfoBox(
          '10개 위험 명령(DTC 삭제·ECU 리셋·UDS·CAN 헤더 등)이 모두 차단되어야 다음 단계로 진행합니다.\n'
          '실제 차량에는 어떤 명령도 전송하지 않습니다.',
          AppColors.primary,
        ),
        const SizedBox(height: 12),

        // 테스트 버튼
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _step1Running ? null : _runStep1,
            icon: _step1Running
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.security, size: 16),
            label: Text(
              _step1Running ? '테스트 실행 중…' : '위험 명령 차단 테스트 실행',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _blockResults == null
                  ? AppColors.danger
                  : (_step1Passed ? AppColors.success : AppColors.danger),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        // 결과
        if (_blockResults != null) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: _blockResults!.map((r) => Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      r.blocked ? Icons.block : Icons.warning_amber_rounded,
                      size: 13,
                      color: r.blocked
                          ? const Color(0xFF4ADE80)
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      r.command,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF38BDF8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      r.blocked ? 'BLOCKED ✓' : 'ALLOWED ✗',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: r.blocked
                            ? const Color(0xFF4ADE80)
                            : Colors.orange,
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 8),
          _buildPassBadge(
            _step1Passed,
            _step1Passed
                ? '${_blockResults!.length}개 위험 명령 전부 차단 확인 ✓'
                : '차단 실패 — 차량 연결 금지!',
          ),
        ],

        const SizedBox(height: 20),
        _buildNextButton(
          label: '2단계로 이동 →',
          enabled: _step1Passed,
          onTap: () => setState(() => _phase = _DrivePhase.step2ManualPid),
        ),
      ],
    ),
  );

  // ── Step 2: 수동 PID 테스트 ──────────────────────────────────────────────
  Widget _buildStep2View() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhaseHeader(
          '2단계: 수동 PID 테스트',
          '4개 PID를 각각 한 번씩 요청해 차량이 정상 응답하는지 확인합니다.\n정차 상태에서 진행하세요.',
        ),
        const SizedBox(height: 16),
        _buildInfoBox(
          '010C(RPM) · 010D(속도) · 0111(스로틀) · 0104(엔진부하)\n'
          '4개 PID 모두 에러 없이 응답해야 3단계로 진행합니다.\n'
          'NO DATA 응답은 해당 PID 미지원을 의미할 수 있습니다.',
          AppColors.warning,
        ),
        const SizedBox(height: 14),

        // 4개 PID 행
        ..._testPids.map((info) {
          final log = _pidResults[info.pid];
          return _PidTestRow(
            pidInfo:   info,
            result:    log,
            isRunning: _step2Running && log == null,
            onTest:    () => _testPid(info.pid),
          );
        }),

        const SizedBox(height: 16),
        _buildNextButton(
          label: '3단계로 이동 →',
          enabled: _step2Passed,
          onTap: () => setState(() => _phase = _DrivePhase.step3Stationary),
        ),
      ],
    ),
  );

  // ── Step 3: 정차 폴링 테스트 ─────────────────────────────────────────────
  Widget _buildStep3View() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhaseHeader(
          '3단계: 정차 저주기 폴링 테스트 (10초)',
          'P단 정차 상태에서 5회 × 2초 간격으로 폴링해 통신 안정성을 확인합니다.',
        ),
        const SizedBox(height: 16),
        _buildInfoBox(
          '010C → 010D → 0111 → 0104 순서로 각 PID를 500ms 간격으로 요청합니다.\n'
          '에러 없이 5회 완료되어야 다음 단계로 진행합니다.',
          AppColors.primary,
        ),
        const SizedBox(height: 12),

        // 진행 상황
        if (_step3Running || _step3Progress > 0) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '폴링 진행: $_step3Progress / $_step3Total',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    if (_step3Running)
                      const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _step3Progress / _step3Total,
                  backgroundColor: AppColors.border,
                  color: _step3Result?.passed == false
                      ? AppColors.danger
                      : AppColors.success,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 테스트 버튼
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _step3Running ? null : _runStep3,
            icon: _step3Running
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(
              _step3Running ? '폴링 테스트 진행 중…' : '정차 폴링 테스트 시작',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _step3Result == null
                  ? AppColors.primary
                  : (_step3Passed ? AppColors.success : AppColors.danger),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),

        // 결과
        if (_step3Result != null) ...[
          const SizedBox(height: 8),
          _buildPassBadge(
            _step3Passed,
            _step3Passed
                ? '정차 폴링 테스트 통과 — 통신 안정적 ✓'
                : '에러 발생: ${_step3Result!.error}',
          ),
        ],

        const SizedBox(height: 20),
        _buildNextButton(
          label: '4단계로 이동 →',
          enabled: _step3Passed,
          onTap: () => setState(() => _phase = _DrivePhase.step4Checklist),
        ),
      ],
    ),
  );

  // ── Step 4: 체크리스트 ────────────────────────────────────────────────────
  Widget _buildStep4View() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPhaseHeader(
          '4단계: 주행 전 안전 체크리스트',
          '아래 항목을 모두 직접 확인하고 체크해야 주행 기록을 시작할 수 있습니다.',
        ),
        const SizedBox(height: 16),

        // 주행 전송 PID 안내 카드
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.primary),
                  SizedBox(width: 6),
                  Text(
                    '주행 중 전송되는 명령 (전부)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: const ['010C', '010D', '0111', '0104'].map((pid) =>
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.successLight,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      pid,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                ).toList(),
              ),
              const SizedBox(height: 6),
              const Text(
                '조향각 · 방향지시등 · Raw CAN · 제조사 PID · DTC 삭제 · ECU 리셋은 전송하지 않습니다.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 체크리스트
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: _checklistItems.asMap().entries.map((e) {
              final i    = e.key;
              final item = e.value;
              return CheckboxListTile(
                value:    _checks[i],
                onChanged: (v) => setState(() => _checks[i] = v ?? false),
                activeColor:    AppColors.primary,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0),
                dense: true,
                title: Text(
                  item,
                  style: TextStyle(
                    fontSize: 13,
                    color: _checks[i]
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        // VIN 확인
        if (_vin.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'VIN: $_vin'
                    '${_carModel.isNotEmpty ? "  ($_carModel)" : ""}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.success,
                        fontFamily: 'monospace'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 시작 버튼
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: _allChecked ? _startRecording : null,
            icon: const Icon(Icons.fiber_manual_record,
                size: 18, color: Colors.white),
            label: const Text(
              '주행 기록 시작',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              disabledBackgroundColor: AppColors.border,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        if (!_allChecked)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(
              child: Text(
                '모든 항목을 체크해야 주행 기록을 시작할 수 있습니다',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textHint),
              ),
            ),
          ),
      ],
    ),
  );

  // ── 주행 기록 화면 ────────────────────────────────────────────────────────
  Widget _buildRecordingView() {
    final sample = _currentSample;
    final score  = _scoreEngine.score;

    return Column(
      children: [
        // 상단 상태 바
        Container(
          color: AppColors.danger.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    color: AppColors.danger, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              const Text(
                '주행 기록 중 · 앱 조작 최소화',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger),
              ),
              const Spacer(),
              Text(
                '샘플: ${_dataSource?.totalSamples ?? 0}',
                style: AppTextStyles.captionHint,
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 안전점수
                _buildScoreCard(score),
                const SizedBox(height: 14),

                // 4개 센서 메트릭
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  children: [
                    _buildLargeMetric(
                      '속도',
                      sample != null ? sample.speed.toInt().toString() : '--',
                      'km/h',
                      AppColors.primary,
                      Icons.speed_rounded,
                    ),
                    _buildLargeMetric(
                      'RPM',
                      sample != null ? sample.rpm.toInt().toString() : '--',
                      'rpm',
                      AppColors.success,
                      Icons.rotate_right_rounded,
                    ),
                    _buildLargeMetric(
                      '스로틀',
                      sample != null ? sample.throttle.toInt().toString() : '--',
                      '%',
                      AppColors.warning,
                      Icons.tune_rounded,
                    ),
                    _buildLargeMetric(
                      '엔진 부하',
                      sample != null ? sample.engineLoad.toInt().toString() : '--',
                      '%',
                      const Color(0xFFEA580C),
                      Icons.memory_rounded,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 폴링 상태
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.sync_rounded,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '폴링 중: 010C → 010D → 0111 → 0104 (500ms 간격)',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppColors.primary),
                        ),
                      ),
                      if ((_dataSource?.totalErrors ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.dangerLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '에러 ${_dataSource!.totalErrors}',
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 최근 감점 이벤트
                if (_recentEvents.isNotEmpty) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '감점 이벤트 (${_recentEvents.length}건)',
                      style: AppTextStyles.caption,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._recentEvents.take(5).map((e) => _buildEventTile(e)),
                ],
                const SizedBox(height: 16),

                // 중단 버튼
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: _stopRecording,
                    icon: const Icon(Icons.stop_circle_outlined,
                        color: AppColors.danger, size: 18),
                    label: const Text(
                      '주행 기록 종료',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 자동 중단 화면 ────────────────────────────────────────────────────────
  Widget _buildAutoStoppedView() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const SizedBox(height: 32),
        Container(
          width: 64, height: 64,
          decoration: const BoxDecoration(
              color: AppColors.dangerLight, shape: BoxShape.circle),
          child: const Icon(Icons.warning_amber_rounded,
              size: 32, color: AppColors.danger),
        ),
        const SizedBox(height: 16),
        const Text('데이터 수집 자동 중단', style: AppTextStyles.h3),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.dangerLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.danger.withValues(alpha: 0.4)),
          ),
          child: Text(
            _dataSource?.stopReason ??
                'OBD 통신 안정성 문제로 데이터 수집을 중단했습니다. 차량 상태를 확인하세요.',
            style: const TextStyle(
                fontSize: 13, color: AppColors.danger, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              _tripEndTime = DateTime.now();
              _finalResult = _scoreEngine.buildResult();
              setState(() => _phase = _DrivePhase.report);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('주행 결과 보기',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('홈으로',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    ),
  );

  // ── 주행 리포트 화면 ──────────────────────────────────────────────────────
  Widget _buildReportView() {
    final result = _finalResult;
    final ds     = _dataSource;

    // 실제 전송된 명령 종류 집계
    final cmdCounts = <String, int>{};
    for (final log in (ds?.commandLog ?? <ObdDriveLog>[])) {
      if (log.allowed) cmdCounts[log.command] = (cmdCounts[log.command] ?? 0) + 1;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 리포트 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Text('주행 리포트', style: AppTextStyles.h2),
                const SizedBox(height: 16),
                Text(
                  result != null ? '${result.score}' : '--',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.w700,
                    color: _scoreColor(result?.score ?? 100),
                    height: 1,
                  ),
                ),
                const Text('/ 100점 안전점수', style: AppTextStyles.captionHint),
                if (result != null && result.totalPenalty > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '총 -${result.totalPenalty}점 · 이벤트 ${result.events.length}건',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 통신 투명성 보고
          const Text('전송 명령 투명성 리포트', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                if (_tripStartTime != null)
                  _buildReportRow('주행 시간', () {
                    final end = _tripEndTime ?? DateTime.now();
                    final dur = end.difference(_tripStartTime!);
                    final m = dur.inMinutes;
                    final s = dur.inSeconds % 60;
                    return '${m}분 ${s}초';
                  }()),
                _buildReportRow('총 샘플 수', '${ds?.totalSamples ?? 0}회'),
                _buildReportRow('통신 에러 수',
                    ds?.totalErrors != null && ds!.totalErrors > 0
                        ? '${ds.totalErrors}회'
                        : '0회 (정상)'),
                _buildReportRow('차단된 명령',
                    ds?.blockedAttempts != null && ds!.blockedAttempts > 0
                        ? '${ds.blockedAttempts}회 차단'
                        : '없음 ✓'),
                const Divider(height: 16, color: AppColors.divider),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '실제 전송된 명령 (표준 PID만)',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 8),
                if (cmdCounts.isEmpty)
                  const Text('기록된 명령 없음',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textHint))
                else
                  ...cmdCounts.entries.map((e) => _buildReportRow(
                        e.key,
                        '${e.value}회',
                        mono: true,
                        color: AppColors.success,
                      )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 이벤트 요약
          if (result != null && result.events.isNotEmpty) ...[
            const Text('감점 이벤트 요약', style: AppTextStyles.h3),
            const SizedBox(height: 8),
            ...result.events.take(20).map((e) => _buildEventTile(e)),
            const SizedBox(height: 16),
          ],

          // 홈으로
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('홈으로',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // ── 헬퍼 위젯 ─────────────────────────────────────────────────────────────

  Widget _buildPhaseHeader(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppTextStyles.h3),
      const SizedBox(height: 4),
      Text(subtitle,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
    ],
  );

  Widget _buildInfoBox(String text, Color color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: color, height: 1.5),
    ),
  );

  Widget _buildPassBadge(bool passed, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: passed ? AppColors.successLight : AppColors.dangerLight,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: passed
            ? AppColors.success.withValues(alpha: 0.4)
            : AppColors.danger.withValues(alpha: 0.4),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          passed ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 14,
          color: passed ? AppColors.success : AppColors.danger,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: passed ? AppColors.success : AppColors.danger,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildNextButton({
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) => SizedBox(
    width: double.infinity,
    height: 50,
    child: ElevatedButton(
      onPressed: enabled ? onTap : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        disabledBackgroundColor: AppColors.border,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _buildScoreCard(int score) {
    final color = _scoreColor(score);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            _isTripActive ? '$score' : '--',
            style: TextStyle(
              fontSize: 60,
              fontWeight: FontWeight.w700,
              color: _isTripActive ? color : AppColors.border,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          const Text('안전점수', style: AppTextStyles.captionHint),
          if (_isTripActive && score < 100) ...[
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '총 -${100 - score}점 감점',
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLargeMetric(
    String label, String value, String unit,
    Color color, IconData icon,
  ) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: AppTextStyles.caption),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            value,
            style: TextStyle(
                fontSize: 28, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 3),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(unit, style: AppTextStyles.captionHint),
          ),
        ]),
      ],
    ),
  );

  Widget _buildEventTile(DriveEvent event) {
    final color = event.penalty >= 4
        ? AppColors.danger
        : event.penalty == 3
            ? const Color(0xFFEA580C)
            : AppColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '-${event.penalty}점',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              event.description,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(String label, String value,
      {bool mono = false, Color? color}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color ?? AppColors.textSecondary,
                  fontFamily: mono ? 'monospace' : null,
                  fontWeight: mono ? FontWeight.w700 : null,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: color ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );

  Color _scoreColor(int score) {
    if (score >= 90) return AppColors.success;
    if (score >= 70) return AppColors.warning;
    return AppColors.danger;
  }
}

// ── PID 테스트 행 위젯 ─────────────────────────────────────────────────────────
class _PidTestRow extends StatelessWidget {
  final _PidInfo     pidInfo;
  final ObdDriveLog? result;
  final bool         isRunning;
  final VoidCallback onTest;

  const _PidTestRow({
    required this.pidInfo,
    required this.result,
    required this.isRunning,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final r      = result;
    final passed = r != null && !r.isError && !r.isBlocked;
    final Color statusColor;
    final String statusLabel;

    if (r == null) {
      statusColor  = AppColors.border;
      statusLabel  = '미테스트';
    } else if (r.isBlocked) {
      statusColor  = AppColors.danger;
      statusLabel  = 'BLOCKED';
    } else if (r.isError) {
      statusColor  = AppColors.danger;
      statusLabel  = r.error ?? 'ERROR';
    } else {
      statusColor  = AppColors.success;
      statusLabel  = r.parsedValue ?? '응답 수신';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: passed
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // PID + 라벨
          SizedBox(
            width: 90,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pidInfo.pid,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(pidInfo.label, style: AppTextStyles.captionHint),
              ],
            ),
          ),

          // 결과
          Expanded(
            child: Text(
              statusLabel,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontFamily: r != null ? 'monospace' : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // 상태 아이콘
          if (passed)
            const Icon(Icons.check_circle_rounded,
                size: 16, color: AppColors.success)
          else if (r != null && r.isError)
            const Icon(Icons.error_rounded, size: 16, color: AppColors.danger),

          const SizedBox(width: 8),

          // 요청 버튼
          SizedBox(
            height: 32,
            child: ElevatedButton(
              onPressed: isRunning ? null : onTest,
              style: ElevatedButton.styleFrom(
                backgroundColor: passed ? AppColors.success : AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: Text(
                passed ? '재테스트' : (isRunning ? '…' : '요청'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
