import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/enums/obd_connection_mode.dart';
import '../../../core/utils/app_mode_controller.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../home_screen.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_text_styles.dart';

/// OBD 스캐너 연결 화면
///
/// - 실제 ELM327 BLE 스캐너를 검색·연결한다.
/// - 스캐너가 없을 경우 "스캐너 없이 체험하기" 로 모의 데이터 모드로 진입한다.
/// - 개발자용 모드 선택 UI는 사용자에게 노출하지 않는다.
class ScannerConnectScreen extends StatefulWidget {
  /// true이면 홈에서 재연결 시 — 연결 완료 후 pop으로 복귀
  final bool isReconnect;
  const ScannerConnectScreen({super.key, this.isReconnect = false});

  @override
  State<ScannerConnectScreen> createState() => _ScannerConnectScreenState();
}

class _ScannerConnectScreenState extends State<ScannerConnectScreen> {
  final ObdDatasource _obd = ObdDatasource();

  List<ScanResult> _scanResults    = [];
  bool _isScanning      = false;
  bool _isConnecting    = false;
  bool _isAutoConnecting = false;
  bool _scanDone        = false;     // 스캔 1회 완료 여부

  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    // 이미 연결된 경우 즉시 처리
    if (ObdDatasource.connected != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onConnectSuccess());
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    if (!_obd.isConnected) _obd.dispose();
    super.dispose();
  }

  // ── 권한 요청 → 자동 연결 시도 → 스캔 ──────────────────────────
  Future<void> _startScanFlow() async {
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
    if (savedId == null) { await _startScan(); return; }

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
    await _startScan(autoConnectId: savedId);
  }

  Future<void> _startScan({String? autoConnectId}) async {
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();

    setState(() {
      _isScanning   = true;
      _scanDone     = false;
      _scanResults  = [];
    });

    _scanSubscription = _obd.scanDevices().listen((results) {
      if (!mounted) return;
      setState(() => _scanResults = results);

      if (autoConnectId != null && !_isConnecting) {
        final match =
            results.where((r) => r.device.remoteId.str == autoConnectId);
        if (match.isNotEmpty) _connect(match.first.device);
      }
    });

    await Future.delayed(const Duration(seconds: 10));
    if (mounted) setState(() { _isScanning = false; _scanDone = true; });
  }

  Future<void> _connect(BluetoothDevice device) async {
    // 최종 안전 확인 다이얼로그
    if (!AppModeController().warningConfirmed) {
      final confirmed = await _showSafetyConfirm();
      if (!confirmed || !mounted) return;
      AppModeController().warningConfirmed = true;
    }

    setState(() => _isConnecting = true);

    // 실차 연결 → 표준 PID 읽기 전용 모드
    AppModeController().setMode(ObdConnectionMode.realReadOnlyDrive);

    final success = await _obd.connect(device);
    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      _onConnectSuccess();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('연결에 실패했습니다. 스캐너를 확인 후 다시 시도해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onConnectSuccess() {
    if (widget.isReconnect) {
      Navigator.pop(context);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  // ── 모의 데이터 체험 ─────────────────────────────────────────────
  Future<void> _enterDemoMode() async {
    AppModeController().setMode(ObdConnectionMode.mock);

    final prefs = await SharedPreferences.getInstance();
    // 이미 저장된 VIN이 없으면 임시 설정
    if ((prefs.getString('vin') ?? '').isEmpty) {
      await prefs.setString('auth_token', 'DEMO_TOKEN');
      await prefs.setString('vin', 'DEMO-VIN-00000000');
      await prefs.setString('car_model', '체험 차량');
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  Future<bool> _showSafetyConfirm() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
                SizedBox(width: 8),
                Text('연결 전 확인', style: AppTextStyles.h3),
              ],
            ),
            content: const Text(
              '본 앱은 차량에 읽기 전용 OBD-II 표준 명령만 전송합니다.\n\n'
              '전송 명령: ATZ, ATE0, 010C, 010D, 0111, 0104 등\n'
              '제어·초기화·삭제 명령은 전혀 전송하지 않습니다.\n\n'
              '위 내용을 확인하고 연결하시겠습니까?',
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
                  backgroundColor: AppColors.primary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('확인 후 연결',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('스캐너 연결', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: widget.isReconnect,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),

            // 상단 BLE 아이콘
            _BleIcon(isScanning: _isScanning || _isAutoConnecting,
                     isConnecting: _isConnecting),
            const SizedBox(height: 20),

            // 상태 텍스트
            Text(
              _isConnecting
                  ? '연결 중입니다...'
                  : _isAutoConnecting
                      ? '이전 기기에 자동 연결 중...'
                      : _isScanning
                          ? '주변 스캐너를 검색하고 있습니다...'
                          : _scanResults.isNotEmpty
                              ? '${_scanResults.length}개 스캐너 발견'
                              : _scanDone
                                  ? '스캐너를 찾지 못했습니다'
                                  : 'OBD-II 스캐너를 차량에 연결해주세요',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              _isConnecting || _isAutoConnecting || _isScanning
                  ? '잠시 기다려주세요'
                  : 'ELM327 블루투스 OBD-II 어댑터를 차량 OBD 포트에\n꽂은 후 검색하세요',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),

            // 스캔 결과 목록
            if (_scanResults.isNotEmpty) ...[
              ..._scanResults.map((r) => _DeviceCard(
                    device: r.device,
                    rssi: r.rssi,
                    isConnecting: _isConnecting,
                    onConnect: () => _connect(r.device),
                  )),
              const SizedBox(height: 16),
            ],

            // 스캔 버튼
            if (!_isConnecting) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  icon: _isScanning || _isAutoConnecting
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.bluetooth_searching,
                          color: Colors.white, size: 20),
                  label: Text(
                    _isScanning
                        ? '검색 중...'
                        : _isAutoConnecting
                            ? '자동 연결 중...'
                            : _scanDone
                                ? '다시 검색'
                                : '스캐너 검색',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                  onPressed: (_isScanning || _isAutoConnecting)
                      ? null
                      : _startScanFlow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 구분선 + 체험 모드
              const Row(
                children: [
                  Expanded(child: Divider(color: AppColors.divider)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('또는',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textHint)),
                  ),
                  Expanded(child: Divider(color: AppColors.divider)),
                ],
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _enterDemoMode,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border, width: 1.2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    '스캐너 없이 체험하기',
                    style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '실제 차량 연결 없이 모의 데이터로 기능을 체험합니다',
                style: TextStyle(fontSize: 11, color: AppColors.textHint),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── 위젯: BLE 아이콘 ─────────────────────────────────────────────────────────
class _BleIcon extends StatelessWidget {
  final bool isScanning;
  final bool isConnecting;
  const _BleIcon({required this.isScanning, required this.isConnecting});

  @override
  Widget build(BuildContext context) {
    final color = isConnecting
        ? AppColors.success
        : isScanning
            ? AppColors.primary
            : AppColors.textHint;
    final bgColor = isConnecting
        ? AppColors.successLight
        : isScanning
            ? AppColors.primaryLight
            : const Color(0xFFF1F5F9);

    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isConnecting
            ? Icons.bluetooth_connected
            : isScanning
                ? Icons.bluetooth_searching
                : Icons.bluetooth,
        size: 44,
        color: color,
      ),
    );
  }
}

// ── 위젯: 발견된 기기 카드 ───────────────────────────────────────────────────
class _DeviceCard extends StatelessWidget {
  final BluetoothDevice device;
  final int rssi;
  final bool isConnecting;
  final VoidCallback onConnect;

  const _DeviceCard({
    required this.device,
    required this.rssi,
    required this.isConnecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : '알 수 없는 기기';
    final signalIcon = rssi > -60
        ? Icons.signal_wifi_4_bar
        : rssi > -75
            ? Icons.network_wifi_3_bar
            : Icons.network_wifi_1_bar;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_outlined,
              size: 22, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(device.remoteId.str,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          ),
          Icon(signalIcon, size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: isConnecting ? null : onConnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: isConnecting
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('연결',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
