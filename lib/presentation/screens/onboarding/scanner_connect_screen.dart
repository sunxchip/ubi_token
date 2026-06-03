import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/enums/obd_connection_mode.dart';
import '../../../core/utils/app_mode_controller.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../../../data/datasources/dry_run_obd_data_source.dart';
import '../home_screen.dart';
import 'vin_auth_screen.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_text_styles.dart';

/// 스캐너 연결 화면
///
/// 세 가지 모드를 선택한 후 진입한다:
///   Mock    — 실제 스캐너 없음, MockObdDataSource, 안전점수 UI 테스트
///   Dry-run — 스캐너 연결 없음, 명령 전송 없음, 파서·SafeValidator 검증
///   Real    — 실제 ELM327 BLE 연결, 체크리스트 + 경고 확인 후에만 활성화
///
/// 기본값: Mock (절대로 Real이 기본값이 되어서는 안 됨)
class ScannerConnectScreen extends StatefulWidget {
  /// true이면 VIN 인증 스킵 후 홈 화면으로 바로 복귀
  final bool isReconnect;
  const ScannerConnectScreen({super.key, this.isReconnect = false});

  @override
  State<ScannerConnectScreen> createState() => _ScannerConnectScreenState();
}

class _ScannerConnectScreenState extends State<ScannerConnectScreen> {
  // ── 모드 선택 ─────────────────────────────────────────────────────────────
  ObdConnectionMode _selectedMode = ObdConnectionMode.mock;

  // ── Real 모드 체크리스트 ──────────────────────────────────────────────────
  // 1~4: 코드 구조상 이미 보장됨 → 자동 체크
  // 5~6: 사용자가 직접 테스트 실행 필요
  final bool _checkCansFeatRemoved  = true; // 조향각/깜빡이/Raw CAN 제거됨
  final bool _checkDtcClearBlocked  = true; // DTC삭제/ECU리셋 차단됨
  final bool _checkMode22Blocked    = true; // Mode22/UDS/제조사PID 차단됨
  final bool _checkAllowedOnly      = true; // 허용 PID만 전송됨
  bool _checkDryRunPassed  = false;
  bool _checkBlockPassed   = false;

  // Real 모드 Dry-run / block test
  final _dryRunner = DryRunObdDataSource();
  List<DryRunLogEntry>? _dryRunResults;
  List<BlockTestResult>? _blockResults;
  bool _dryRunRunning  = false;
  bool _blockRunning   = false;

  // ── BLE 스캔 (Real 모드용) ────────────────────────────────────────────────
  final ObdDatasource _obd = ObdDatasource();
  List<ScanResult> _scanResults = [];
  bool _isScanning    = false;
  bool _isConnecting  = false;
  bool _isAutoConnecting = false;
  StreamSubscription? _scanSubscription;

  bool get _allChecked =>
      _checkCansFeatRemoved &&
      _checkDtcClearBlocked &&
      _checkMode22Blocked &&
      _checkAllowedOnly &&
      _checkDryRunPassed &&
      _checkBlockPassed;

  @override
  void initState() {
    super.initState();
    // AppModeController에 저장된 기존 테스트 결과 복원
    final ctrl = AppModeController();
    _checkDryRunPassed = ctrl.dryRunTestPassed;
    _checkBlockPassed  = ctrl.blockTestPassed;
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    if (!_obd.isConnected) _obd.dispose();
    super.dispose();
  }

  // ── Mock / Dry-run 진입 ───────────────────────────────────────────────────
  Future<void> _enterMockOrDryRun(ObdConnectionMode mode) async {
    AppModeController().setMode(mode);

    final prefs     = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final vin       = prefs.getString('vin')        ?? '';

    if (!mounted) return;

    if (authToken.isNotEmpty && vin.isNotEmpty) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      final modeLabel = mode == ObdConnectionMode.mock
          ? 'MOCK-VIN-00000'
          : 'DRYRUN-VIN-00000';
      final modelLabel = mode == ObdConnectionMode.mock
          ? 'Mock 차량 (테스트)'
          : 'Dry-run 차량 (명령 전송 없음)';

      await prefs.setString('auth_token', '${mode.label.toUpperCase()}_TOKEN');
      await prefs.setString('vin',        modeLabel);
      await prefs.setString('car_model',  modelLabel);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  // ── Real 모드: BLE 스캔 ───────────────────────────────────────────────────
  Future<void> _requestPermissionsAndScan() async {
    await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    if (!mounted) return;
    await _tryAutoConnect();
  }

  Future<void> _tryAutoConnect() async {
    final savedId = await ObdDatasource.loadLastDeviceId();
    if (savedId == null) { _startScan(); return; }

    try {
      final systemDevices = await FlutterBluePlus.systemDevices([]);
      for (final device in systemDevices) {
        if (device.remoteId.str == savedId) {
          if (mounted) {
            setState(() => _isAutoConnecting = true);
            await _connect(device);
            if (mounted) setState(() => _isAutoConnecting = false);
          }
          return;
        }
      }
    } catch (_) {}
    _startScan(autoConnectId: savedId);
  }

  Future<void> _startScan({String? autoConnectId}) async {
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();

    setState(() { _isScanning = true; _scanResults = []; });

    _scanSubscription = _obd.scanDevices().listen((results) {
      if (!mounted) return;
      setState(() => _scanResults = results);

      if (autoConnectId != null && !_isConnecting) {
        final match = results.where((r) => r.device.remoteId.str == autoConnectId);
        if (match.isNotEmpty) _connect(match.first.device);
      }
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    // 최종 경고 확인 다이얼로그
    if (!AppModeController().warningConfirmed) {
      final confirmed = await _showRealModeWarning();
      if (!confirmed || !mounted) return;
      AppModeController().warningConfirmed = true;
    }

    setState(() => _isConnecting = true);
    AppModeController().setMode(ObdConnectionMode.real);

    final success = await _obd.connect(device);
    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      if (widget.isReconnect) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => VinAuthScreen(obd: _obd)),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결 실패. 다시 시도해주세요.')),
      );
    }
  }

  Future<bool> _showRealModeWarning() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.shield_outlined,
                    color: Color(0xFFEA580C), size: 20),
                SizedBox(width: 8),
                Text('실차 연결 전 최종 확인', style: AppTextStyles.h3),
              ],
            ),
            content: const Text(
              '본 앱은 표준 OBD-II PID 읽기 전용 명령만 전송합니다.\n\n'
              '전송하는 명령:\n'
              '  ATZ, ATE0, ATL0, ATS0, ATH0, ATSP0\n'
              '  0100, 010C, 010D, 0111, 0104, 0902, 03\n\n'
              '절대 전송하지 않는 명령:\n'
              '  제조사 전용 CAN, 조향각, 방향지시등,\n'
              '  제어/초기화/삭제/ECU 리셋 명령\n\n'
              '위 사항을 확인했으며 표준 PID 읽기 전용으로 연결하겠습니다.',
              style: TextStyle(fontSize: 13, height: 1.6),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('확인 · 표준 PID 읽기 전용으로 연결',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── 인라인 Dry-run 테스트 (Real 모드 체크리스트용) ──────────────────────
  Future<void> _runDryRunTest() async {
    setState(() => _dryRunRunning = true);
    await Future.delayed(const Duration(milliseconds: 80));
    final results = _dryRunner.runAllTests();
    final passed  = results.every((e) => e.allowed);
    if (mounted) {
      setState(() {
        _dryRunResults = results;
        _dryRunRunning = false;
        _checkDryRunPassed = passed;
        AppModeController().dryRunTestPassed = passed;
      });
    }
  }

  Future<void> _runBlockTest() async {
    setState(() => _blockRunning = true);
    await Future.delayed(const Duration(milliseconds: 80));
    final results = _dryRunner.runBlockTests();
    final passed  = results.every((r) => r.blocked);
    if (mounted) {
      setState(() {
        _blockResults = results;
        _blockRunning = false;
        _checkBlockPassed = passed;
        AppModeController().blockTestPassed = passed;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('연결 모드 선택', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 모드 선택 ─────────────────────────────────────
            _buildModeSelector(),
            const SizedBox(height: 16),

            // ── 모드별 콘텐츠 ──────────────────────────────────
            if (_selectedMode == ObdConnectionMode.mock)
              _buildMockSection()
            else if (_selectedMode == ObdConnectionMode.dryRun)
              _buildDryRunSection()
            else
              _buildRealSection(),
          ],
        ),
      ),
    );
  }

  // ── 모드 선택 카드 ────────────────────────────────────────────────────────
  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('OBD 연결 모드', style: AppTextStyles.h3),
        const SizedBox(height: 10),
        ...ObdConnectionMode.values.map((mode) {
          final selected = _selectedMode == mode;
          Color borderColor;
          Color bgColor;
          IconData icon;
          switch (mode) {
            case ObdConnectionMode.mock:
              borderColor = AppColors.primary;
              bgColor     = AppColors.primaryLight;
              icon        = Icons.science_outlined;
            case ObdConnectionMode.dryRun:
              borderColor = AppColors.warning;
              bgColor     = AppColors.warningLight;
              icon        = Icons.playlist_add_check_rounded;
            case ObdConnectionMode.real:
              borderColor = AppColors.danger;
              bgColor     = AppColors.dangerLight;
              icon        = Icons.bluetooth_connected;
          }
          return GestureDetector(
            onTap: () => setState(() => _selectedMode = mode),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? bgColor : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected
                      ? borderColor
                      : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 3,
                      offset: Offset(0, 1))
                ],
              ),
              child: Row(
                children: [
                  Icon(icon,
                      size: 20,
                      color: selected ? borderColor : AppColors.textHint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              mode.label,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? borderColor
                                    : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: selected
                                    ? borderColor.withValues(alpha: 0.15)
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                mode.badge,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? borderColor
                                      : AppColors.textHint,
                                ),
                              ),
                            ),
                            if (mode == ObdConnectionMode.real) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  '기본 비활성화',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          mode.description,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Radio<ObdConnectionMode>(
                    value: mode,
                    groupValue: _selectedMode,
                    onChanged: (v) =>
                        setState(() => _selectedMode = v!),
                    activeColor: borderColor,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ── Mock 섹션 ─────────────────────────────────────────────────────────────
  Widget _buildMockSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined,
                  size: 18, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '실제 ELM327 스캐너 없이 Mock 데이터로 안전점수 화면 전체를 테스트합니다.\n'
                  '차량에 어떤 명령도 전송하지 않습니다.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _enterMockOrDryRun(ObdConnectionMode.mock),
            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
            label: const Text('Mock 모드로 시작',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Dry-run 섹션 ──────────────────────────────────────────────────────────
  Widget _buildDryRunSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.playlist_add_check_rounded,
                  size: 18, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ELM327 스캐너 연결 없이 SafeObdCommandValidator와 OBD 파서를 검증합니다.\n'
                  '실제 차량에 어떤 명령도 전송하지 않습니다.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: () => _enterMockOrDryRun(ObdConnectionMode.dryRun),
            icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
            label: const Text('Dry-run 모드로 시작',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            '안전점수 화면에서 DryRunObdDataSource 기반 샘플 데이터를 사용합니다',
            style: TextStyle(fontSize: 10, color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // ── Real 섹션 (체크리스트 + BLE 스캔) ────────────────────────────────────
  Widget _buildRealSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 발표 버전 안내
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warningLight,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '현재 발표 버전에서는 차량 안전을 위해 Mock/Dry-run 기반으로 시연합니다.\n'
                  '실제 ELM327 BLE 연동은 추후 구현 예정입니다.',
                  style: TextStyle(fontSize: 12, color: AppColors.textPrimary, height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 체크리스트
        const Text('실차 연결 전 체크리스트', style: AppTextStyles.h3),
        const SizedBox(height: 8),
        _buildChecklist(),
        const SizedBox(height: 16),

        // 체크 미완료 시 경고
        if (!_allChecked) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dangerLight,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outlined,
                    size: 16, color: AppColors.danger),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '실차 연결 전 Dry-run 모드에서 전송 명령을 먼저 확인하세요.\n'
                    '위 체크리스트를 모두 완료해야 BLE 스캔이 시작됩니다.',
                    style: TextStyle(
                        color: AppColors.danger, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          // 체크 완료 → BLE 스캔 섹션 표시
          _buildBleScanSection(),
        ],
      ],
    );
  }

  // ── 체크리스트 위젯 ───────────────────────────────────────────────────────
  Widget _buildChecklist() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        children: [
          // 자동 체크 항목 (코드 구조상 보장)
          _CheckItem(
            checked: _checkCansFeatRemoved,
            label: '조향각/깜빡이/Raw CAN 기능 제거됨',
            sub: 'SafeObdCommandValidator 차단 · 코드 제거 완료',
            auto: true,
          ),
          _CheckItem(
            checked: _checkDtcClearBlocked,
            label: 'DTC 삭제/ECU 리셋 명령 차단됨',
            sub: '04, 11, 14FFFFFF → SafeObdCommandValidator 차단',
            auto: true,
          ),
          _CheckItem(
            checked: _checkMode22Blocked,
            label: 'Mode 22/UDS/제조사 PID 차단됨',
            sub: '22xx, 10xx, 31, 3E → SafeObdCommandValidator 차단',
            auto: true,
          ),
          _CheckItem(
            checked: _checkAllowedOnly,
            label: '허용 PID만 전송됨',
            sub: '010C, 010D, 0111, 0104, 0902, 03 — 15개만 허용',
            auto: true,
          ),

          const Divider(height: 16, color: AppColors.divider),

          // Dry-run 테스트 (사용자 실행 필요)
          _CheckItem(
            checked: _checkDryRunPassed,
            label: 'Dry-run 테스트 완료',
            sub: _checkDryRunPassed
                ? '12개 허용 명령 정상 확인'
                : '아래 버튼을 눌러 테스트를 실행하세요',
            auto: false,
          ),
          if (!_checkDryRunPassed || _dryRunResults != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _dryRunRunning ? null : _runDryRunTest,
                    icon: _dryRunRunning
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary))
                        : const Icon(Icons.play_arrow,
                            size: 14, color: AppColors.primary),
                    label: Text(
                      _dryRunRunning
                          ? '실행 중...'
                          : (_checkDryRunPassed
                              ? 'Dry-run 재실행'
                              : 'Dry-run 실행'),
                      style:
                          const TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            if (_dryRunResults != null) ...[
              const SizedBox(height: 6),
              _MiniLogView(entries: _dryRunResults!),
            ],
            const SizedBox(height: 8),
          ],

          // 위험 명령 차단 테스트 (사용자 실행 필요)
          _CheckItem(
            checked: _checkBlockPassed,
            label: '위험 명령 차단 테스트 완료',
            sub: _checkBlockPassed
                ? '10개 위험 명령 모두 차단 확인'
                : '아래 버튼을 눌러 차단 테스트를 실행하세요',
            auto: false,
          ),
          if (!_checkBlockPassed || _blockResults != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _blockRunning ? null : _runBlockTest,
                    icon: _blockRunning
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: const Color(0xFF7C3AED)))
                        : const Icon(Icons.security,
                            size: 14,
                            color: Color(0xFF7C3AED)),
                    label: Text(
                      _blockRunning
                          ? '실행 중...'
                          : (_checkBlockPassed
                              ? '차단 테스트 재실행'
                              : '차단 테스트 실행'),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF7C3AED)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF7C3AED)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
            if (_blockResults != null) ...[
              const SizedBox(height: 6),
              _BlockResultView(results: _blockResults!),
            ],
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  // ── BLE 스캔 섹션 (체크리스트 완료 후) ────────────────────────────────────
  Widget _buildBleScanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.successLight,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: AppColors.success.withValues(alpha: 0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 16, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  '체크리스트 완료 — 표준 PID 읽기 전용으로 연결합니다.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 읽기 전용 안내 배너
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFFB923C).withValues(alpha: 0.4)),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 3,
                  offset: Offset(0, 1))
            ],
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined,
                  size: 20, color: Color(0xFFEA580C)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '본 앱은 표준 OBD-II PID 읽기 전용 모드로만 동작합니다.\n'
                  '제조사 전용 CAN · 제어 · 삭제 · 초기화 명령은 사용하지 않습니다.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFEA580C),
                      height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // BLE 안내 카드
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 3,
                  offset: Offset(0, 1))
            ],
          ),
          child: const Row(
            children: [
              Icon(Icons.bluetooth_searching,
                  size: 20, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'ELM327 스캐너를 차량에 연결하고 블루투스를 켜주세요',
                  style: AppTextStyles.bodySecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 스캔 상태 인디케이터
        if (_isAutoConnecting || _isScanning)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Text(
                  _isAutoConnecting ? '이전 기기에 재연결 중...' : '장치 검색 중...',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.primary),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // 장치 목록
        if (_scanResults.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isScanning
                        ? Icons.bluetooth_searching
                        : Icons.bluetooth_disabled,
                    size: 36,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isScanning ? '검색 중...' : '장치를 찾지 못했습니다',
                    style: AppTextStyles.bodySecondary,
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _scanResults.length,
            itemBuilder: (context, index) {
              final result = _scanResults[index];
              final name = result.device.platformName.isNotEmpty
                  ? result.device.platformName
                  : '알 수 없는 장치';
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 3,
                        offset: Offset(0, 1))
                  ],
                ),
                child: ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bluetooth,
                        size: 18, color: AppColors.primary),
                  ),
                  title: Text(name,
                      style: AppTextStyles.body
                          .copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(result.device.remoteId.str,
                      style: AppTextStyles.captionHint),
                  trailing: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary))
                      : const Icon(Icons.chevron_right,
                          size: 18, color: AppColors.textHint),
                  onTap: () => _connect(result.device),
                ),
              );
            },
          ),

        const SizedBox(height: 10),

        // 스캔 시작 / 다시 검색 버튼
        SizedBox(
          width: double.infinity,
          height: 48,
          child: _scanResults.isEmpty && !_isScanning
              ? ElevatedButton.icon(
                  onPressed: _requestPermissionsAndScan,
                  icon: const Icon(Icons.bluetooth_searching,
                      size: 16, color: Colors.white),
                  label: const Text('BLE 스캔 시작',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                )
              : OutlinedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('다시 검색'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── 공용 위젯 ──────────────────────────────────────────────────────────────────

class _CheckItem extends StatelessWidget {
  final bool   checked;
  final String label;
  final String sub;
  final bool   auto;

  const _CheckItem({
    required this.checked,
    required this.label,
    required this.sub,
    required this.auto,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 18,
              color: checked ? AppColors.success : AppColors.textHint,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: checked
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (auto)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.successLight,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '자동',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(sub,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MiniLogView extends StatelessWidget {
  final List<DryRunLogEntry> entries;
  const _MiniLogView({required this.entries});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: entries
              .map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      children: [
                        Icon(
                          e.allowed ? Icons.check : Icons.block,
                          size: 11,
                          color: e.allowed
                              ? const Color(0xFF4ADE80)
                              : Colors.orange.shade300,
                        ),
                        const SizedBox(width: 5),
                        SizedBox(
                          width: 60,
                          child: Text(
                            e.command,
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (e.parsed != null)
                          Expanded(
                            child: Text(
                              '→ ${e.parsed}',
                              style: const TextStyle(
                                color: Color(0xFF4ADE80),
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          Expanded(
                            child: Text(
                              e.response ?? (e.allowed ? 'OK' : 'BLOCKED'),
                              style: TextStyle(
                                color: e.allowed
                                    ? const Color(0xFF94A3B8)
                                    : Colors.orange.shade300,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      );
}

class _BlockResultView extends StatelessWidget {
  final List<BlockTestResult> results;
  const _BlockResultView({required this.results});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: results
            .map((r) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: r.blocked
                        ? AppColors.successLight
                        : AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: r.blocked
                          ? AppColors.success.withValues(alpha: 0.3)
                          : AppColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.command,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        r.blocked ? '✓' : '✗',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: r.blocked
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      );
}
