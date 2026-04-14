import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/datasources/obd_datasource.dart';
import '../../core/constants/obd_constants.dart';

/// 실차 검증용 PID 진단 화면
/// - AT 명령 터미널: 직접 명령 입력 → 원시 응답 확인
/// - 라이브 모니터: 모든 PID 값을 실시간으로 표시
/// 차 연결 시 이 화면에서 0x2B0(조향각), 0x4B0(방향지시등) 파싱이 맞는지 확인
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
  double _steering   = 0;
  TurnSignalState _signals = const TurnSignalState(left: false, right: false, hazard: false);
  String _rawSteeringFrame = '-';
  String _rawSignalFrame   = '-';
  bool   _isPolling  = false;

  // ── 빠른 명령 버튼 목록 ──────────────────────────────
  static const _quickCmds = [
    ('ATZ',        'ELM 리셋'),
    ('ATE0',       '에코 OFF'),
    ('ATH1',       '헤더 ON'),
    ('ATSP6',      '프로토콜6'),
    ('010D',       '속도'),
    ('010C',       'RPM'),
    ('0902',       'VIN'),
    ('ATCAF0\nATCF 2B0\nATCM FFF\nATMA', '조향각 캡처'),
    ('ATCAF0\nATCF 4B0\nATCM FFF\nATMA', '방향지시등 캡처'),
    ('ATCAF1\nATCF 000\nATCM 000', '필터 초기화'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cmdController.dispose();
    _scrollCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── 터미널: 명령 전송 ─────────────────────────────────
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

    // 여러 줄 명령 (빠른 버튼에서 사용)
    final lines = trimmed.split('\n');
    for (final line in lines) {
      final response = await _obd!.sendRaw(line.trim());
      if (!mounted) return;
      setState(() => _terminalLog.add(_TermEntry.received(line.trim(), response)));
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
      final speed = await _obd!.getSpeed();
      final rpm   = await _obd!.getRpm();
      if (!mounted) return;
      setState(() { _speed = speed; _rpm = rpm; });
    } catch (_) {}
    // 조향각/방향지시등은 CAN 필터 전환이 필요하므로 자동 폴링 제외
    // → 하단 "캡처" 버튼으로 수동 확인
  }

  // ── 조향각 단일 캡처 (원시 응답 확인용) ──────────────
  Future<void> _captureRawSteering() async {
    if (_obd == null) return;
    setState(() => _rawSteeringFrame = '읽는 중...');
    final raw = await _obd!.sendRaw('ATCAF0');
    await _obd!.sendRaw('ATCF ${ObdConstants.canIdSteering}');
    await _obd!.sendRaw('ATCM FFF');
    final frame = await _obd!.sendRaw('ATMA');
    await _obd!.sendRaw('ATCAF1');
    await _obd!.sendRaw('ATCF 000');
    await _obd!.sendRaw('ATCM 000');
    if (!mounted) return;
    setState(() => _rawSteeringFrame = '${raw.trim()} | $frame');
  }

  Future<void> _captureRawSignal() async {
    if (_obd == null) return;
    setState(() => _rawSignalFrame = '읽는 중...');
    await _obd!.sendRaw('ATCAF0');
    await _obd!.sendRaw('ATCF ${ObdConstants.canIdBcm}');
    await _obd!.sendRaw('ATCM FFF');
    final frame = await _obd!.sendRaw('ATMA');
    await _obd!.sendRaw('ATCAF1');
    await _obd!.sendRaw('ATCF 000');
    await _obd!.sendRaw('ATCM 000');
    if (!mounted) return;
    setState(() => _rawSignalFrame = frame.trim());
  }

  // 필터 없이 전체 CAN 트래픽 15줄 캡처 → 깜빡이 CAN ID 탐색용
  Future<void> _scanAllCan() async {
    if (_obd == null) return;
    setState(() => _rawSignalFrame = '전체 스캔 중...\n(깜빡이 켜고 기다리세요)');
    await _obd!.sendRaw('ATCAF0');
    await _obd!.sendRaw('ATCF 000');
    await _obd!.sendRaw('ATCM 000');
    final frames = await _obd!.sendRaw('ATMA', maxLines: 15);
    await _obd!.sendRaw('ATCAF1');
    await _obd!.sendRaw('ATCF 000');
    await _obd!.sendRaw('ATCM 000');
    if (!mounted) return;

    // 캡처된 CAN ID 목록만 추출해서 표시
    final ids = frames
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('AT') && !l.contains('>'))
        .map((l) => l.split(' ').first.toUpperCase())
        .where((id) => RegExp(r'^[0-9A-F]{3}$').hasMatch(id))
        .toSet()
        .toList()
      ..sort();

    setState(() {
      _rawSignalFrame = ids.isEmpty
          ? '(프레임 없음 - 시동 상태 확인)'
          : '활성 CAN ID:\n${ids.join(', ')}\n\n원시:\n${frames.trim()}';
    });
  }

  @override
  Widget build(BuildContext context) {
    final connected = _obd != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: Row(
          children: [
            const Text('PID 진단', style: TextStyle(color: Colors.white)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: connected ? Colors.green.shade700 : Colors.red.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                connected ? '연결됨 · ${_obd!.deviceName}' : '연결 없음',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'AT 터미널'),
            Tab(text: '라이브 모니터'),
          ],
        ),
      ),
      body: !connected
          ? const Center(
              child: Text('OBD 장치에 먼저 연결해주세요',
                  style: TextStyle(color: Colors.grey)),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTerminal(),
                _buildLiveMonitor(),
              ],
            ),
    );
  }

  // ── AT 터미널 ─────────────────────────────────────────
  Widget _buildTerminal() {
    return Column(
      children: [
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
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
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
                          const Text('> ', style: TextStyle(color: Color(0xFF38BDF8), fontFamily: 'monospace')),
                          Expanded(
                            child: Text(
                              entry.cmd,
                              style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'monospace', fontSize: 13),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onLongPress: () {
                              Clipboard.setData(ClipboardData(text: entry.response ?? ''));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('복사됨'), duration: Duration(seconds: 1)),
                              );
                            },
                            child: Text(
                              entry.response ?? '',
                              style: TextStyle(
                                color: (entry.response?.contains('ERROR') ?? false) ||
                                        (entry.response?.contains('?') ?? false)
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
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    hintText: 'AT 명령 입력 (예: 010D)',
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
                  icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                  onPressed: _clearLog,
                ),
              IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(color: Color(0xFF38BDF8), strokeWidth: 2),
                      )
                    : const Icon(Icons.send, color: Color(0xFF38BDF8)),
                onPressed: _isSending ? null : () => _sendCmd(_cmdController.text),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 라이브 모니터 ─────────────────────────────────────
  Widget _buildLiveMonitor() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 폴링 제어
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _togglePolling,
                  icon: Icon(_isPolling ? Icons.stop : Icons.play_arrow),
                  label: Text(_isPolling ? '모니터 중지' : '모니터 시작'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPolling ? Colors.red.shade700 : Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 표준 OBD (속도/RPM)
          _buildSectionLabel('표준 OBD-II (검증됨)'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _MonitorCard(label: '속도', value: '${_speed.toInt()}', unit: 'km/h', color: const Color(0xFF38BDF8))),
              const SizedBox(width: 10),
              Expanded(child: _MonitorCard(label: 'RPM', value: '${_rpm.toInt()}', unit: 'rpm', color: const Color(0xFF34D399))),
            ],
          ),
          const SizedBox(height: 20),

          // 조향각 (실차 검증 필요)
          _buildSectionLabel('조향각 센서 CAN 0x${ObdConstants.canIdSteering}  ⚠ 실차 검증 필요'),
          const SizedBox(height: 8),
          _MonitorCard(
            label: '조향각 (파싱값)',
            value: _steering.toStringAsFixed(1),
            unit: '°',
            color: const Color(0xFFA78BFA),
          ),
          const SizedBox(height: 8),
          _RawFrameBox(
            label: '원시 프레임',
            raw: _rawSteeringFrame,
            onCapture: _captureRawSteering,
          ),
          const SizedBox(height: 8),
          _buildParseGuide(
            '파싱 규칙',
            'byte 0-1 → signed 16-bit big-endian ÷ 10 = 각도(°)\n'
            '예) "2B0 05 E1 ..." → 0x05E1 = 1505 → 150.5°\n'
            '⚠ 부호/배율이 다르면 obd_constants.dart 수정',
          ),
          const SizedBox(height: 20),

          // 방향지시등 (실차 검증 필요)
          _buildSectionLabel('BCM CAN 0x${ObdConstants.canIdBcm}  ⚠ 실차 검증 필요'),
          const SizedBox(height: 8),
          Row(
            children: [
              _SignalIndicator(label: '좌', active: _signals.left,   color: Colors.orange),
              const SizedBox(width: 10),
              _SignalIndicator(label: '우', active: _signals.right,  color: Colors.orange),
              const SizedBox(width: 10),
              _SignalIndicator(label: '비상', active: _signals.hazard, color: Colors.red),
            ],
          ),
          const SizedBox(height: 8),
          _RawFrameBox(
            label: '원시 프레임 (0x${ObdConstants.canIdBcm})',
            raw: _rawSignalFrame,
            onCapture: _captureRawSignal,
          ),
          const SizedBox(height: 8),
          // CAN ID 못 찾을 때 전체 스캔
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade800),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠ 응답 없음이면 CAN ID가 틀린 것',
                  style: TextStyle(color: Colors.orange, fontSize: 11),
                ),
                const SizedBox(height: 4),
                const Text(
                  '깜빡이 켠 상태에서 아래 버튼으로 전체 스캔 → 활성 ID 확인',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _scanAllCan,
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('CAN 전체 스캔 (깜빡이 켜고 누르세요)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade800,
                      foregroundColor: Colors.white,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildParseGuide(
            '파싱 규칙 (obd_constants.dart)',
            'turnLeftMask  = 0x${ObdConstants.turnLeftMask.toRadixString(16).padLeft(2, '0')}  → byte0 & 마스크 ≠ 0 이면 좌회전\n'
            'turnRightMask = 0x${ObdConstants.turnRightMask.toRadixString(16).padLeft(2, '0')}  → byte0 & 마스크 ≠ 0 이면 우회전\n'
            '⚠ 실제 프레임의 byte/bit 위치 확인 후 수정',
          ),
          const SizedBox(height: 20),

          // 수정 가이드
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('검증 후 수정 방법',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 8),
                const Text(
                  '1. 깜빡이 켜고 "원시 프레임 캡처" 눌러서 byte 값 확인\n'
                  '2. 핸들 돌리고 "원시 프레임 캡처" 눌러서 byte 값 확인\n'
                  '3. obd_constants.dart에서 마스크/배율 수정\n'
                  '4. obd_datasource.dart의 _parseSteeringAngle() 수정',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) => Text(
        text,
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _buildParseGuide(String title, String body) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
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
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(unit, style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RawFrameBox extends StatelessWidget {
  final String label;
  final String raw;
  final VoidCallback onCapture;

  const _RawFrameBox({
    required this.label,
    required this.raw,
    required this.onCapture,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10)),
                  const SizedBox(height: 4),
                  Text(
                    raw,
                    style: const TextStyle(
                      color: Color(0xFF4ADE80),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onCapture,
              child: const Text('캡처', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
            ),
          ],
        ),
      );
}

class _SignalIndicator extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;

  const _SignalIndicator({
    required this.label,
    required this.active,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.2) : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? color : const Color(0xFF334155),
              width: active ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(Icons.arrow_upward, color: active ? color : Colors.grey, size: 20),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? color : Colors.grey,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
}
