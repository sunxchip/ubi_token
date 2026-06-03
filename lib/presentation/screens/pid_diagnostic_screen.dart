import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/datasources/obd_datasource.dart';
import '../../data/datasources/dry_run_obd_data_source.dart';
import '../../data/datasources/its_datasource.dart';
import '../../data/models/road_speed_limit.dart';
import '../../core/enums/obd_connection_mode.dart';
import '../../core/utils/app_mode_controller.dart';
import '../../core/utils/obd_pid_parser.dart';
import '../../core/utils/safe_obd_command_validator.dart';
import '../../core/utils/speed_limit_checker.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

/// OBD-II 진단 화면 (읽기 전용)
///
/// 허용 명령: ATZ, ATE0, ATL0, ATS0, ATH0, ATSP0,
///            0100, 0104, 0105, 010C, 010D, 0111, 012F, 0902, 03
///
/// 차단: Raw CAN, CAN 헤더 설정, UDS, 제어/삭제/초기화 명령
class PidDiagnosticScreen extends StatefulWidget {
  const PidDiagnosticScreen({super.key});

  @override
  State<PidDiagnosticScreen> createState() => _PidDiagnosticScreenState();
}

class _PidDiagnosticScreenState extends State<PidDiagnosticScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ObdDatasource? get _obd => ObdDatasource.connected;

  // ── 터미널 탭 ─────────────────────────────────────────
  final _cmdController = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final List<_TermEntry> _terminalLog = [];
  bool _isSending = false;

  // ── 라이브 모니터 탭 ──────────────────────────────────
  Timer? _pollTimer;
  double _speed      = 0;
  double _rpm        = 0;
  double _throttle   = 0;
  double _engineLoad = 0;
  bool   _isPolling  = false;

  // ── 허용된 빠른 명령 버튼 목록 ───────────────────────
  // CAN 헤더, Raw CAN, 제어 명령은 포함하지 않음
  static const _quickCmds = [
    ('ATZ',   'ELM 리셋'),
    ('ATE0',  '에코 OFF'),
    ('ATH0',  '헤더 OFF'),
    ('ATSP0', '프로토콜 자동'),
    ('0100',  'PID 확인'),
    ('010D',  '속도'),
    ('010C',  'RPM'),
    ('0111',  '스로틀'),
    ('0104',  '엔진부하'),
    ('0902',  'VIN'),
    ('03',    'DTC 읽기'),
  ];

  // ── PID 파서 테스트 탭 ────────────────────────────────
  final _customInputController = TextEditingController();
  String _customPidType = 'RPM (010C)';
  String _customParseResult = '';

  // ── 안전 점검 탭 ──────────────────────────────────────
  final _dryRunner = DryRunObdDataSource();
  List<DryRunLogEntry>? _dryRunResults;
  List<BlockTestResult>? _blockResults;
  bool _dryRunRunning   = false;
  bool _blockRunning    = false;
  bool _allowedExpanded = false;

  // ── 도로/제한속도 탭 ──────────────────────────────────
  final _its = ItsDatasource();
  bool _roadLoading = false;
  Position? _currentPosition;
  TrafficInfo? _trafficInfo;
  RoadSpeedLimit? _matchedVsl;
  String _roadErrorMsg = '';

  // ── VSL 디버그 패널 ───────────────────────────────────
  bool _debugLoading = false;
  VslDebugResult? _debugResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cmdController.dispose();
    _scrollCtrl.dispose();
    _customInputController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── 터미널: 명령 전송 (SafeObdCommandValidator 검증 필수) ──
  Future<void> _sendCmd(String cmd) async {
    if (_obd == null || _isSending) return;
    final trimmed = cmd.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isSending = true;
      _terminalLog.add(_TermEntry.sent(trimmed));
      if (_terminalLog.length > 200) _terminalLog.removeRange(0, 50);
    });
    _cmdController.clear();
    _scrollToBottom();

    final lines = trimmed.split('\n');
    for (final line in lines) {
      final lineCmd = line.trim();
      if (lineCmd.isEmpty) continue;
      try {
        final response = await _obd!.sendCommand(lineCmd);
        if (!mounted) return;
        setState(() => _terminalLog.add(_TermEntry.received(lineCmd, response)));
      } on UnsafeObdCommandException catch (e) {
        if (!mounted) return;
        setState(() => _terminalLog.add(
          _TermEntry.received(lineCmd, '⛔ ${e.toString()}'),
        ));
      } catch (e) {
        if (!mounted) return;
        setState(() => _terminalLog.add(
          _TermEntry.received(lineCmd, '오류: $e'),
        ));
      }
      _scrollToBottom();
      await Future.delayed(const Duration(milliseconds: 100));
    }

    setState(() => _isSending = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearLog() => setState(() => _terminalLog.clear());

  // ── 라이브 모니터: 폴링 시작/중지 ─────────────────────
  void _togglePolling() {
    if (_isPolling) {
      _pollTimer?.cancel();
      setState(() => _isPolling = false);
    } else {
      setState(() => _isPolling = true);
      _poll();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 800), (_) => _poll());
    }
  }

  Future<void> _poll() async {
    if (_obd == null || !mounted) return;
    try {
      final speed      = await _obd!.getSpeed();
      final rpm        = await _obd!.getRpm();
      final throttle   = await _obd!.getThrottle();
      final engineLoad = await _obd!.getEngineLoad();
      if (!mounted) return;
      setState(() {
        _speed      = speed;
        _rpm        = rpm;
        _throttle   = throttle;
        _engineLoad = engineLoad;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final connected = _obd != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Row(
          children: [
            const Text('PID 진단', style: AppTextStyles.h2),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: connected ? AppColors.successLight : AppColors.dangerLight,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                connected ? '연결됨' : '연결 없음',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: connected ? AppColors.success : AppColors.danger,
                ),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'AT 터미널'),
            Tab(text: '라이브 모니터'),
            Tab(text: 'PID 파서'),
            Tab(text: '도로정보'),
            Tab(text: '안전 점검'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          !connected
              ? const Center(
                  child: Text('OBD 장치에 먼저 연결해주세요',
                      style: TextStyle(color: Colors.grey)))
              : _buildTerminal(),
          !connected
              ? const Center(
                  child: Text('OBD 장치에 먼저 연결해주세요',
                      style: TextStyle(color: Colors.grey)))
              : _buildLiveMonitor(),
          _buildPidParserTest(),
          _buildRoadInfoTab(),
          _buildSafetyCheckTab(),
        ],
      ),
    );
  }

  // ── AT 터미널 ─────────────────────────────────────────
  Widget _buildTerminal() {
    return Column(
      children: [
        // 안전 안내 배너
        Container(
          width: double.infinity,
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: const Text(
            '⛔ 허용 명령만 전송됩니다. 금지 명령은 자동 차단됩니다.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
        ),

        // 빠른 명령 버튼
        Container(
          color: const Color(0xFF1E293B),
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            children: _quickCmds.map((item) {
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => _sendCmd(item.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.$2,
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 12),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // 로그 출력
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(12),
            itemCount: _terminalLog.length,
            itemBuilder: (_, i) {
              final entry = _terminalLog[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: entry.isSent
                    ? Row(
                        children: [
                          const Text('> ',
                              style: TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontFamily: 'monospace')),
                          Expanded(
                            child: Text(
                              entry.cmd,
                              style: const TextStyle(
                                  color: Color(0xFF38BDF8),
                                  fontFamily: 'monospace',
                                  fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onLongPress: () {
                              Clipboard.setData(
                                  ClipboardData(text: entry.response ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('복사됨'),
                                    duration: Duration(seconds: 1)),
                              );
                            },
                            child: Text(
                              entry.response ?? '',
                              style: TextStyle(
                                color: (entry.response?.contains('⛔') ?? false)
                                    ? Colors.orange.shade300
                                    : (entry.response?.contains('ERROR') ??
                                                false) ||
                                            (entry.response?.contains('?') ??
                                                false)
                                        ? Colors.red.shade300
                                        : const Color(0xFF4ADE80),
                                fontFamily: 'monospace',
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
              );
            },
          ),
        ),

        // 입력창
        Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmdController,
                  style: const TextStyle(
                      color: Colors.white, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: '허용 명령 입력 (예: 010D)',
                    hintStyle: TextStyle(color: Colors.grey),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onSubmitted: _sendCmd,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
              if (_terminalLog.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.grey, size: 20),
                  onPressed: _clearLog,
                ),
              IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Color(0xFF38BDF8), strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Color(0xFF38BDF8)),
                onPressed: _isSending
                    ? null
                    : () => _sendCmd(_cmdController.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 라이브 모니터 (표준 OBD-II PID 4종) ───────────────
  Widget _buildLiveMonitor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 안전 안내
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Text(
              '표준 OBD-II PID 읽기 전용 모드\n'
              '010D 속도 · 010C RPM · 0111 스로틀 · 0104 엔진부하',
              style: TextStyle(
                  color: AppColors.primary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _togglePolling,
              icon: Icon(_isPolling ? Icons.stop : Icons.play_arrow, size: 16),
              label: Text(
                _isPolling ? '모니터 중지' : '모니터 시작',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isPolling ? AppColors.danger : AppColors.success,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionLabel('표준 OBD-II (검증됨)'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _MonitorCard(
                      label: '속도',
                      value: '${_speed.toInt()}',
                      unit: 'km/h',
                      color: AppColors.primary)),
              const SizedBox(width: 10),
              Expanded(
                  child: _MonitorCard(
                      label: 'RPM',
                      value: '${_rpm.toInt()}',
                      unit: 'rpm',
                      color: AppColors.success)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _MonitorCard(
                      label: '스로틀',
                      value: _throttle.toStringAsFixed(1),
                      unit: '%',
                      color: AppColors.warning)),
              const SizedBox(width: 10),
              Expanded(
                  child: _MonitorCard(
                      label: '엔진부하',
                      value: _engineLoad.toStringAsFixed(1),
                      unit: '%',
                      color: AppColors.danger)),
            ],
          ),
          const SizedBox(height: 20),

          // 제거된 기능 안내
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('제외된 기능', style: AppTextStyles.h3),
                SizedBox(height: 8),
                Text(
                  '조향각 및 방향지시등 데이터는 제조사 고유 CAN 신호 해석이 '
                  '필요하고 안전성 검증이 필요하므로 본 구현 범위에서 제외하였다.\n\n'
                  'Raw CAN, CAN 헤더 설정(ATSH/ATCRA 등), UDS 명령, '
                  '제어/삭제/초기화 명령은 SafeObdCommandValidator에 의해 '
                  '차단된다.',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── PID 파서 테스트 탭 ─────────────────────────────────
  Widget _buildPidParserTest() {
    final pidTypes = [
      'RPM (010C)',
      '속도 (010D)',
      '스로틀 (0111)',
      '엔진부하 (0104)',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'ELM327 응답 문자열을 직접 입력하면 파싱 결과를 확인할 수 있습니다.\n'
              'OBD 연결 없이 동작하며, 실차 응답이 이상할 때 디버깅용으로 사용하세요.',
              style: TextStyle(
                  color: AppColors.primary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 16),

          _buildSectionLabel('샘플 파싱 테스트 (사전 정의 케이스)'),
          const SizedBox(height: 8),
          ...ObdPidParser.sampleTestCases.map((tc) => _ParserTestRow(tc: tc)),
          const SizedBox(height: 20),

          _buildSectionLabel('직접 입력 테스트'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('PID 종류:', style: AppTextStyles.caption),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _customPidType,
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 12),
                      underline: const SizedBox(),
                      items: pidTypes
                          .map((t) =>
                              DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _customPidType = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _customInputController,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace',
                      fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '예: 410C1AF8  또는  7E8 04 41 0C 1A F8',
                    hintStyle:
                        const TextStyle(color: AppColors.textHint, fontSize: 12),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final input = _customInputController.text.trim();
                      if (input.isEmpty) return;
                      String? result;
                      if (_customPidType.startsWith('RPM')) {
                        final v = ObdPidParser.parseRpm(input);
                        result = v != null ? '${v.toStringAsFixed(1)} rpm' : null;
                      } else if (_customPidType.startsWith('속도')) {
                        final v = ObdPidParser.parseSpeed(input);
                        result = v != null
                            ? '${v.toStringAsFixed(1)} km/h'
                            : null;
                      } else if (_customPidType.startsWith('스로틀')) {
                        final v = ObdPidParser.parseThrottle(input);
                        result = v != null ? '${v.toStringAsFixed(1)}%' : null;
                      } else {
                        final v = ObdPidParser.parseEngineLoad(input);
                        result = v != null ? '${v.toStringAsFixed(1)}%' : null;
                      }
                      setState(() {
                        _customParseResult =
                            result ?? '파싱 실패 — 응답 형식 확인 필요';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('파싱 실행',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                if (_customParseResult.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _customParseResult.contains('실패')
                          ? AppColors.dangerLight
                          : AppColors.successLight,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _customParseResult.contains('실패')
                            ? AppColors.danger.withValues(alpha: 0.3)
                            : AppColors.success.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '결과: $_customParseResult',
                      style: TextStyle(
                        color: _customParseResult.contains('실패')
                            ? AppColors.danger
                            : AppColors.success,
                        fontFamily: 'monospace',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSectionLabel('PID 변환식 참고'),
          const SizedBox(height: 8),
          _buildParseGuide(
            'OBD-II 서비스01 응답 변환식',
            'RPM (010C):       ((A×256)+B) / 4\n'
            '속도 (010D):      A  (km/h)\n'
            '스로틀 (0111):    A×100/255  (%)\n'
            '엔진부하 (0104):  A×100/255  (%)\n'
            '\n'
            '응답 마커: 41 = 서비스01 응답, 다음 바이트 = PID\n'
            '헤더 OFF(ATH0): "41 PID DATA..." 형식',
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── 안전 점검 탭 ──────────────────────────────────────────────────────────
  Widget _buildSafetyCheckTab() {
    final ctrl = AppModeController();
    final mode = ctrl.mode;
    final modeColor = switch (mode) {
      ObdConnectionMode.mock   => AppColors.primary,
      ObdConnectionMode.dryRun => AppColors.warning,
      ObdConnectionMode.real   => AppColors.danger,
    };

    final allPassed     = _dryRunResults != null &&
        _dryRunResults!.every((e) => e.allowed);
    final blockAllPassed = _blockResults != null &&
        _blockResults!.every((e) => e.blocked);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 현재 모드 배지 ─────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: modeColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: modeColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      mode.sendsToVehicle
                          ? Icons.wifi_tethering
                          : Icons.shield_outlined,
                      size: 18,
                      color: modeColor,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '현재 모드: ${mode.label}  (${mode.badge})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: modeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  mode.description,
                  style: TextStyle(
                      fontSize: 11, color: modeColor, height: 1.5),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      mode.sendsToVehicle
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 14,
                      color: mode.sendsToVehicle
                          ? AppColors.danger
                          : AppColors.success,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      mode.sendsToVehicle
                          ? '실제 차량으로 명령 전송 활성화'
                          : '실제 차량으로 전송되는 명령 없음',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: mode.sendsToVehicle
                            ? AppColors.danger
                            : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Real 모드 경고
          if (mode == ObdConnectionMode.real) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.4)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppColors.danger),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '실차 연결 전 Dry-run 모드에서 전송 명령을 먼저 확인하세요.\n'
                      '아래 테스트를 실행하여 SafeObdCommandValidator가 정상 동작하는지 확인하세요.',
                      style: TextStyle(
                          color: AppColors.danger, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── 허용 명령 목록 (펼치기/접기) ──────────────────
          _buildSectionLabel('허용 명령 목록 (SafeObdCommandValidator)'),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                setState(() => _allowedExpanded = !_allowedExpanded),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
                boxShadow: const [
                  BoxShadow(
                      color: Colors.black12,
                      blurRadius: 2,
                      offset: Offset(0, 1))
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      const Text('15개 허용 명령',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success)),
                      const Spacer(),
                      Icon(
                          _allowedExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: AppColors.textHint),
                    ],
                  ),
                  if (_allowedExpanded) ...[
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: AppColors.divider),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: const [
                        'ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0',
                        '0100', '0104', '0105', '010C', '010D', '0111',
                        '012F', '0902', '03',
                      ].map((cmd) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color:
                                  AppColors.success.withValues(alpha: 0.3)),
                        ),
                        child: Text(cmd,
                            style: const TextStyle(
                              color: AppColors.success,
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            )),
                      )).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Dry-run 테스트 ─────────────────────────────────
          _buildSectionLabel('Dry-run 허용 명령 테스트'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Text(
              '허용 명령 12개를 샘플 응답으로 테스트합니다.\n'
              '실제 차량에 어떤 명령도 전송하지 않습니다.',
              style: TextStyle(
                  color: AppColors.primary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _dryRunRunning
                  ? null
                  : () async {
                      setState(() => _dryRunRunning = true);
                      await Future.delayed(
                          const Duration(milliseconds: 100));
                      final results = _dryRunner.runAllTests();
                      final passed  = results.every((e) => e.allowed);
                      if (mounted) {
                        setState(() {
                          _dryRunResults  = results;
                          _dryRunRunning  = false;
                          AppModeController().dryRunTestPassed = passed;
                        });
                      }
                    },
              icon: _dryRunRunning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.play_arrow, size: 16),
              label: Text(
                _dryRunRunning ? '테스트 실행 중...' : 'Dry-run 테스트 실행',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _dryRunResults == null
                    ? AppColors.primary
                    : (allPassed ? AppColors.success : AppColors.danger),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (_dryRunResults != null) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: _dryRunResults!.map((e) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          e.allowed
                              ? Icons.check_circle
                              : Icons.block,
                          size: 13,
                          color: e.allowed
                              ? const Color(0xFF4ADE80)
                              : Colors.orange.shade300,
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          width: 72,
                          child: Text(
                            e.command,
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            e.allowed
                                ? (e.response ?? 'NO DATA')
                                : 'BLOCKED',
                            style: TextStyle(
                              color: e.allowed
                                  ? const Color(0xFF94A3B8)
                                  : Colors.orange.shade300,
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (e.parsed != null)
                          Text(
                            '→ ${e.parsed}',
                            style: const TextStyle(
                              color: Color(0xFF4ADE80),
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  allPassed
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 14,
                  color: allPassed ? AppColors.success : AppColors.danger,
                ),
                const SizedBox(width: 5),
                Text(
                  allPassed
                      ? 'Dry-run 테스트 통과 — AppModeController.dryRunTestPassed = true'
                      : 'Dry-run 테스트 실패',
                  style: TextStyle(
                    fontSize: 11,
                    color: allPassed ? AppColors.success : AppColors.danger,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // ── 위험 명령 차단 테스트 ──────────────────────────
          _buildSectionLabel('위험 명령 차단 테스트'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.dangerLight,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
            ),
            child: const Text(
              '10개 위험 명령이 SafeObdCommandValidator에 의해 차단되는지 확인합니다.\n'
              '실제 차량에 어떤 명령도 전송하지 않습니다.',
              style: TextStyle(
                  color: AppColors.danger, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _blockRunning
                  ? null
                  : () async {
                      setState(() => _blockRunning = true);
                      await Future.delayed(
                          const Duration(milliseconds: 100));
                      final results = _dryRunner.runBlockTests();
                      final passed  = results.every((r) => r.blocked);
                      if (mounted) {
                        setState(() {
                          _blockResults = results;
                          _blockRunning = false;
                          AppModeController().blockTestPassed = passed;
                        });
                      }
                    },
              icon: _blockRunning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.security, size: 16),
              label: Text(
                _blockRunning ? '차단 테스트 실행 중...' : '위험 명령 차단 테스트 실행',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _blockResults == null
                    ? const Color(0xFF7C3AED)
                    : (blockAllPassed
                        ? AppColors.success
                        : AppColors.danger),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          if (_blockResults != null) ...[
            const SizedBox(height: 8),
            ..._blockResults!.map((r) {
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: r.blocked
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.danger.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      r.blocked
                          ? Icons.block
                          : Icons.warning_amber_rounded,
                      size: 14,
                      color:
                          r.blocked ? AppColors.success : AppColors.danger,
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.command,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: r.blocked
                            ? AppColors.successLight
                            : AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        r.blocked ? 'BLOCKED ✓' : 'ALLOWED ✗',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: r.blocked
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  blockAllPassed
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  size: 14,
                  color:
                      blockAllPassed ? AppColors.success : AppColors.danger,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    blockAllPassed
                        ? '위험 명령 10개 모두 차단 확인 — AppModeController.blockTestPassed = true'
                        : '차단 실패한 명령 존재! 실차 연결 전 수정 필요',
                    style: TextStyle(
                      fontSize: 11,
                      color: blockAllPassed
                          ? AppColors.success
                          : AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // ── 현재 앱에서 실제 전송 가능한 명령 목록 ─────────
          _buildSectionLabel('실제 차량 전송 가능 명령 (Real 모드 한정)'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ELM327 초기화 (6개)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                ),
                SizedBox(height: 4),
                Text(
                  'ATZ · ATE0 · ATL0 · ATS0 · ATH0 · ATSP0',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textPrimary),
                ),
                SizedBox(height: 10),
                Text(
                  '표준 OBD-II 서비스01 PID (7개)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                ),
                SizedBox(height: 4),
                Text(
                  '0100 · 0104 · 0105 · 010C · 010D · 0111 · 012F',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textPrimary),
                ),
                SizedBox(height: 10),
                Text(
                  '차량 정보 / DTC 읽기 (2개)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary),
                ),
                SizedBox(height: 4),
                Text(
                  '0902 (VIN) · 03 (DTC 읽기 전용)',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.textPrimary),
                ),
                SizedBox(height: 10),
                Text(
                  '절대 전송하지 않는 명령 예시',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.danger),
                ),
                SizedBox(height: 4),
                Text(
                  '04(DTC삭제) · 08(온보드제어) · 22xx(제조사PID)\n'
                  'ATSH/ATCRA(CAN헤더) · 10/11/14(UDS) · 2E(ECU쓰기)',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppColors.danger,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── 도로정보 / 제한속도 탭 ───────────────────────────────
  Widget _buildRoadInfoTab() {
    final obdSpeed  = _isPolling ? _speed : null;
    final limitSpeed = _matchedVsl?.effectiveLimitSpeed;
    final isOver = SpeedLimitChecker.isOverSpeed(
      vehicleSpeed: obdSpeed ?? 0,
      limitSpeed: limitSpeed,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Text(
              'trafficInfo: 현재 도로 통행속도 (제한속도 아님)\n'
              'VSL: 가변형 속도제한표지 기반 제한속도\n'
              '두 API 모두 동일한 ITS_API_KEY를 사용합니다.',
              style: TextStyle(
                  color: AppColors.primary, fontSize: 12, height: 1.5),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _roadLoading ? null : _fetchRoadInfo,
              icon: _roadLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 16),
              label: Text(
                _roadLoading ? '조회 중...' : '현재 위치 도로정보 조회',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),

          if (_roadErrorMsg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Text(_roadErrorMsg,
                  style: const TextStyle(
                      color: AppColors.danger, fontSize: 12)),
            ),
          ],

          const SizedBox(height: 16),

          _buildSectionLabel('GPS 위치'),
          const SizedBox(height: 8),
          _InfoCard(rows: [
            _InfoRow2('위도',
                _currentPosition != null
                    ? _currentPosition!.latitude.toStringAsFixed(6)
                    : '-'),
            _InfoRow2('경도',
                _currentPosition != null
                    ? _currentPosition!.longitude.toStringAsFixed(6)
                    : '-'),
          ]),
          const SizedBox(height: 14),

          _buildSectionLabel('trafficInfo (통행속도 — 제한속도 아님)'),
          const SizedBox(height: 8),
          _InfoCard(rows: [
            _InfoRow2('도로명', _trafficInfo?.roadName ?? '-'),
            _InfoRow2('링크 ID', _trafficInfo?.linkId ?? '-'),
            _InfoRow2('통행속도',
                _trafficInfo != null
                    ? '${_trafficInfo!.speed} km/h (실제 차량 속도)'
                    : '-'),
          ]),
          const SizedBox(height: 14),

          _buildSectionLabel('VSL 제한속도'),
          const SizedBox(height: 8),
          _InfoCard(rows: [
            _InfoRow2('VSL ID', _matchedVsl?.vslId ?? '-'),
            _InfoRow2('도로 번호', _matchedVsl?.roadNo ?? '-'),
            _InfoRow2('링크 ID', _matchedVsl?.linkId ?? '-'),
            _InfoRow2('도로 구분', _matchedVsl?.sectionLabel ?? '-'),
            _InfoRow2('제한속도',
                _matchedVsl?.limitSpeed != null
                    ? '${_matchedVsl!.limitSpeed!.toInt()} km/h'
                    : '정보 없음'),
            _InfoRow2('기본 제한속도',
                _matchedVsl?.defaultLimitSpeed != null
                    ? '${_matchedVsl!.defaultLimitSpeed!.toInt()} km/h'
                    : '정보 없음'),
            _InfoRow2('적용 제한속도',
                limitSpeed != null
                    ? '${limitSpeed.toInt()} km/h'
                    : '제한속도 정보 없음'),
          ]),

          if (_matchedVsl == null && _currentPosition != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: const Text(
                '제한속도 정보 없음\n'
                'VSL 정보 미제공 구간이거나 ITS_VSL_API_URL 미설정 상태입니다.',
                style: TextStyle(
                    color: AppColors.warning, fontSize: 12, height: 1.5),
              ),
            ),
          ],

          const SizedBox(height: 14),

          _buildSectionLabel('OBD 차량 속도 vs 제한속도'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isOver ? AppColors.dangerLight : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOver
                    ? AppColors.danger.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
              ],
            ),
            child: Column(
              children: [
                _InfoRow2('OBD 차량 속도',
                    obdSpeed != null
                        ? '${obdSpeed.toInt()} km/h'
                        : '모니터 탭 시작 필요'),
                const Divider(height: 1, color: AppColors.divider),
                _InfoRow2('적용 제한속도',
                    limitSpeed != null
                        ? '${limitSpeed.toInt()} km/h'
                        : '제한속도 정보 없음'),
                const Divider(height: 1, color: AppColors.divider),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('과속 여부', style: AppTextStyles.caption),
                      if (limitSpeed == null)
                        const Text('판단 불가 (제한속도 없음)',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textHint))
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isOver
                                ? AppColors.dangerLight
                                : AppColors.successLight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isOver ? '과속' : '정상',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isOver
                                  ? AppColors.danger
                                  : AppColors.success,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          _buildSectionLabel('VSL API 디버그'),
          const SizedBox(height: 8),

          _DebugButtonGrid(
            loading: _debugLoading,
            onTrafficInfo: _debugTrafficInfo,
            onVslRaw:      _debugVslRaw,
            onVslWithGps:  _debugVslWithGps,
            onLinkIdMatch: _debugLinkIdMatch,
          ),

          if (_debugResult != null) ...[
            const SizedBox(height: 12),
            _VslDebugPanel(result: _debugResult!),
          ],

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: const Text(
              'TODO: 과속 이벤트 연동 예정\n'
              '- EventType.speeding → DriveEvent 생성\n'
              '- 제한속도 + 5km/h 초과 5초 이상 지속: -3점\n'
              '- 제한속도 + 20km/h 초과 5초 이상 지속: -5점\n'
              '- 제한속도 정보 없는 구간은 과속 감점 제외',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<void> _fetchRoadInfo() async {
    setState(() {
      _roadLoading = true;
      _roadErrorMsg = '';
    });

    try {
      bool hasPermission =
          await Geolocator.checkPermission() != LocationPermission.denied;
      if (!hasPermission) await Geolocator.requestPermission();
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() => _currentPosition = pos);

      final traffic = await _its.getRoadTrafficInfo(
          latitude: pos.latitude, longitude: pos.longitude);
      setState(() => _trafficInfo = traffic);

      final vslList = await _its.fetchVslSpeedLimitsAround(
        latitude: pos.latitude,
        longitude: pos.longitude,
        trafficLinkId: traffic?.linkId,
      );

      final matched = _its.findNearestVsl(
        vslList: vslList,
        latitude: pos.latitude,
        longitude: pos.longitude,
        trafficLinkId: traffic?.linkId,
      );
      setState(() => _matchedVsl = matched);

      if (traffic == null && vslList.isEmpty) {
        setState(() => _roadErrorMsg =
            'trafficInfo, VSL 모두 조회 실패. API 키 또는 URL 설정을 확인하세요.');
      }
    } catch (e) {
      setState(() => _roadErrorMsg = '조회 실패: $e');
    } finally {
      setState(() => _roadLoading = false);
    }
  }

  Future<void> _debugTrafficInfo() async {
    setState(() {
      _debugLoading = true;
      _debugResult  = null;
    });
    try {
      final pos = await _getPosition();
      if (pos == null) {
        setState(() => _debugResult = VslDebugResult.configError(
            'GPS 권한이 없거나 위치를 가져올 수 없습니다.'));
        return;
      }
      final info = await _its.getRoadTrafficInfo(
          latitude: pos.latitude, longitude: pos.longitude);
      setState(() => _debugResult = VslDebugResult(
        requestUrl:    'ITS_TRAFFIC_API_URL',
        requestParams: {'lat': pos.latitude, 'lon': pos.longitude},
        statusCode:    info != null ? 200 : 0,
        resultCode:    info != null ? '0' : 'null',
        resultMsg:     info != null ? '성공' : '결과 없음',
        totalCount:    info != null ? '1' : '0',
        firstLinkId:   info?.linkId,
        bodyPreview:   info != null
            ? '도로명: ${info.roadName ?? '-'}\nlinkId: ${info.linkId ?? '-'}\n통행속도: ${info.speed} km/h'
            : '응답 없음',
        errorMsg:      info == null
            ? 'trafficInfo 조회 실패. API 키/URL 확인 필요.'
            : null,
      ));
    } finally {
      setState(() => _debugLoading = false);
    }
  }

  Future<void> _debugVslRaw() async {
    setState(() {
      _debugLoading = true;
      _debugResult  = null;
    });
    try {
      final result = await _its.debugVslCall();
      setState(() => _debugResult = result);
    } finally {
      setState(() => _debugLoading = false);
    }
  }

  Future<void> _debugVslWithGps() async {
    setState(() {
      _debugLoading = true;
      _debugResult  = null;
    });
    try {
      final pos = await _getPosition();
      if (pos == null) {
        setState(() => _debugResult = VslDebugResult.configError(
            'GPS 권한이 없거나 위치를 가져올 수 없습니다.'));
        return;
      }
      final result = await _its.debugVslCall();
      setState(() => _debugResult = result);
    } finally {
      setState(() => _debugLoading = false);
    }
  }

  Future<void> _debugLinkIdMatch() async {
    setState(() {
      _debugLoading = true;
      _debugResult  = null;
    });
    try {
      final pos = await _getPosition();
      if (pos == null) {
        setState(() => _debugResult = VslDebugResult.configError(
            'GPS 권한이 없거나 위치를 가져올 수 없습니다.'));
        return;
      }
      final traffic = await _its.getRoadTrafficInfo(
          latitude: pos.latitude, longitude: pos.longitude);
      final result  = await _its.debugVslCall();
      setState(() => _debugResult = VslDebugResult(
        requestUrl:      result.requestUrl,
        requestParams:   {
          ...result.requestParams,
          'trafficInfo.linkId': traffic?.linkId ?? '(없음)',
          'trafficInfo.speed':
              traffic != null ? '${traffic.speed} km/h (통행속도)' : '(없음)',
          'trafficInfo.road':   traffic?.roadName ?? '(없음)',
        },
        statusCode:      result.statusCode,
        resultCode:      result.resultCode,
        resultMsg:       result.resultMsg,
        totalCount:      result.totalCount,
        firstVslId:      result.firstVslId,
        firstLinkId:     result.firstLinkId,
        firstLimitSpeed: result.firstLimitSpeed,
        firstDefLmtSpeed:result.firstDefLmtSpeed,
        firstCoordX:     result.firstCoordX,
        firstCoordY:     result.firstCoordY,
        bodyPreview:     result.bodyPreview,
        errorMsg:        result.errorMsg,
        is4002:          result.is4002,
      ));
    } finally {
      setState(() => _debugLoading = false);
    }
  }

  Future<Position?> _getPosition() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return null;
      return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      return null;
    }
  }

  Widget _buildSectionLabel(String text) =>
      Text(text, style: AppTextStyles.h3);

  Widget _buildParseGuide(String title, String body) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.caption),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ],
        ),
      );
}

// ── 공용 위젯 ──────────────────────────────────────────

class _ParserTestRow extends StatelessWidget {
  final ParserTestCase tc;
  const _ParserTestRow({required this.tc});

  @override
  Widget build(BuildContext context) {
    final actual = tc.actualOutput;
    final pass   = tc.isPass;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: pass
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.danger.withValues(alpha: 0.3),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pass
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                size: 14,
                color: pass ? AppColors.success : AppColors.danger,
              ),
              const SizedBox(width: 6),
              Text(tc.pid, style: AppTextStyles.label),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '입력: ${tc.rawInput}',
            style: const TextStyle(
                color: AppColors.textSecondary,
                fontFamily: 'monospace',
                fontSize: 11),
          ),
          Text('기대: ${tc.expectedLabel}', style: AppTextStyles.captionHint),
          Text(
            '결과: $actual',
            style: TextStyle(
              color: pass ? AppColors.success : AppColors.danger,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TermEntry {
  final bool isSent;
  final String cmd;
  final String? response;

  _TermEntry.sent(this.cmd)
      : isSent = true,
        response = null;

  _TermEntry.received(this.cmd, this.response) : isSent = false;
}

class _MonitorCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _MonitorCard({
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
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.w700)),
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

// ── 도로정보 탭 공용 위젯 ──────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final List<_InfoRow2> rows;
  const _InfoCard({required this.rows});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
          ],
        ),
        child: Column(
          children: rows.asMap().entries.map((e) {
            final isLast = e.key == rows.length - 1;
            return Column(
              children: [
                e.value,
                if (!isLast)
                  const Divider(height: 1, color: AppColors.divider),
              ],
            );
          }).toList(),
        ),
      );
}

class _InfoRow2 extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow2(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(label, style: AppTextStyles.caption),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                style: AppTextStyles.label,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

// ── VSL 디버그 버튼 그리드 ────────────────────────────────────────────────────

class _DebugButtonGrid extends StatelessWidget {
  final bool loading;
  final VoidCallback onTrafficInfo;
  final VoidCallback onVslRaw;
  final VoidCallback onVslWithGps;
  final VoidCallback onLinkIdMatch;

  const _DebugButtonGrid({
    required this.loading,
    required this.onTrafficInfo,
    required this.onVslRaw,
    required this.onVslWithGps,
    required this.onLinkIdMatch,
  });

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [
            _DebugBtn(
                label: 'trafficInfo\n테스트',
                icon: Icons.traffic,
                onTap: loading ? null : onTrafficInfo),
            const SizedBox(width: 8),
            _DebugBtn(
                label: 'VSL Raw\n호출',
                icon: Icons.api,
                onTap: loading ? null : onVslRaw),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _DebugBtn(
                label: 'GPS 기준\nVSL 조회',
                icon: Icons.my_location,
                onTap: loading ? null : onVslWithGps),
            const SizedBox(width: 8),
            _DebugBtn(
                label: 'linkId 매칭\n테스트',
                icon: Icons.compare_arrows,
                onTap: loading ? null : onLinkIdMatch),
          ]),
          if (loading) ...[
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary)),
                SizedBox(width: 8),
                Text('API 호출 중...',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      );
}

class _DebugBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _DebugBtn({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
            decoration: BoxDecoration(
              color: onTap != null ? AppColors.surface : AppColors.divider,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: onTap != null
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.border),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))
              ],
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 16,
                    color: onTap != null
                        ? AppColors.primary
                        : AppColors.textHint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onTap != null
                          ? AppColors.textPrimary
                          : AppColors.textHint,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// ── VSL 디버그 결과 패널 ──────────────────────────────────────────────────────

class _VslDebugPanel extends StatefulWidget {
  final VslDebugResult result;
  const _VslDebugPanel({required this.result});

  @override
  State<_VslDebugPanel> createState() => _VslDebugPanelState();
}

class _VslDebugPanelState extends State<_VslDebugPanel> {
  bool _bodyExpanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.result;

    if (r.isConfigError) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.settings, size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '설정 오류\n${r.errorMsg!}',
                style: const TextStyle(
                    color: AppColors.warning, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      );
    }

    final isSuccess  = r.isSuccess;
    final headerColor = isSuccess ? AppColors.success : AppColors.danger;
    final headerBg    = isSuccess ? AppColors.successLight : AppColors.dangerLight;
    final headerLabel = isSuccess
        ? 'API 호출 성공  (resultCode: 0)'
        : r.is4002
            ? '필수 파라미터 누락  (resultCode: 4002)'
            : 'API 호출 실패  (resultCode: ${r.resultCode ?? "-"})';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: headerColor.withValues(alpha: 0.35)),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: headerBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(children: [
              Icon(
                  isSuccess
                      ? Icons.check_circle
                      : Icons.error_outline,
                  size: 16,
                  color: headerColor),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(headerLabel,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: headerColor))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.is4002) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      '필수 파라미터 누락 오류입니다.\n'
                      'ITS VSL API 문서에서 필수 요청 파라미터를 확인해야 합니다.',
                      style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text('요청 정보', style: AppTextStyles.h3),
                const SizedBox(height: 6),
                _DebugRow('URL',
                    r.requestUrl.isEmpty ? '(미설정)' : r.requestUrl),
                ...r.requestParams.entries
                    .map((e) => _DebugRow(e.key, e.value.toString())),
                const SizedBox(height: 12),
                const Text('응답 파싱', style: AppTextStyles.h3),
                const SizedBox(height: 6),
                _DebugRow('HTTP statusCode',
                    r.statusCode == 0 ? '-' : r.statusCode.toString()),
                _DebugRow('resultCode',  r.resultCode ?? '-'),
                _DebugRow('resultMsg',   r.resultMsg  ?? '-'),
                _DebugRow('totalCount',  r.totalCount ?? '-'),
                if (r.firstVslId != null || r.firstLinkId != null) ...[
                  const SizedBox(height: 8),
                  const Text('첫 번째 item', style: AppTextStyles.h3),
                  const SizedBox(height: 6),
                  if (r.firstVslId       != null)
                    _DebugRow('vslId', r.firstVslId!),
                  if (r.firstLinkId      != null)
                    _DebugRow('linkId', r.firstLinkId!),
                  if (r.firstLimitSpeed  != null)
                    _DebugRow('limitSpeed', '${r.firstLimitSpeed} km/h'),
                  if (r.firstDefLmtSpeed != null)
                    _DebugRow('defLmtSpeed', '${r.firstDefLmtSpeed} km/h'),
                  if (r.firstCoordX != null)
                    _DebugRow('coordX (경도)', r.firstCoordX!),
                  if (r.firstCoordY != null)
                    _DebugRow('coordY (위도)', r.firstCoordY!),
                ],
                if (r.errorMsg != null && !r.is4002) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(r.errorMsg!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12)),
                  ),
                ],
                if (r.bodyPreview.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _bodyExpanded = !_bodyExpanded),
                    child: Row(children: [
                      const Text('Response Body', style: AppTextStyles.h3),
                      const Spacer(),
                      Icon(
                          _bodyExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: AppColors.textSecondary),
                    ]),
                  ),
                  if (_bodyExpanded) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onLongPress: () {
                        Clipboard.setData(
                            ClipboardData(text: r.bodyPreview));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('응답 복사됨'),
                              duration: Duration(seconds: 1)),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(r.bodyPreview,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontFamily: 'monospace',
                                fontSize: 11,
                                height: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('길게 누르면 복사됩니다',
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textHint)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebugRow extends StatelessWidget {
  final String label;
  final String value;
  const _DebugRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 110,
                child: Text(label, style: AppTextStyles.captionHint)),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      fontFamily: 'monospace')),
            ),
          ],
        ),
      );
}
