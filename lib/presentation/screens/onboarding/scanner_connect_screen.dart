import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../home_screen.dart';
import 'vin_auth_screen.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_text_styles.dart';

class ScannerConnectScreen extends StatefulWidget {
  /// [isReconnect] true 이면 VIN 인증 스킵 후 홈 화면으로 바로 복귀
  final bool isReconnect;
  const ScannerConnectScreen({super.key, this.isReconnect = false});

  @override
  State<ScannerConnectScreen> createState() => _ScannerConnectScreenState();
}

class _ScannerConnectScreenState extends State<ScannerConnectScreen> {
  final ObdDatasource _obd = ObdDatasource();
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  StreamSubscription? _scanSubscription;

  bool _isAutoConnecting = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndScan();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    // 연결 성공 후 전역 인스턴스로 등록된 경우 dispose하지 않음
    // (VinAuthScreen → HomeScreen에서 계속 사용)
    if (!_obd.isConnected) _obd.dispose();
    super.dispose();
  }

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
    if (savedId == null) {
      _startScan();
      return;
    }

    // 이미 시스템에 연결된(본딩된) 기기 중에서 먼저 확인
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

    // 시스템 기기에 없으면 일반 스캔 시작 (발견 시 자동 연결)
    _startScan(autoConnectId: savedId);
  }

  Future<void> _startScan({String? autoConnectId}) async {
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();

    setState(() {
      _isScanning = true;
      _scanResults = [];
    });

    _scanSubscription = _obd.scanDevices().listen((results) {
      if (!mounted) return;
      setState(() => _scanResults = results);

      // 저장된 기기가 스캔 결과에 나타나면 자동 연결
      if (autoConnectId != null && !_isConnecting) {
        final match = results.where(
          (r) => r.device.remoteId.str == autoConnectId,
        );
        if (match.isNotEmpty) {
          _connect(match.first.device);
        }
      }
    });

    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  // ── Mock 모드 진입 ────────────────────────────────────────────────────────
  // 개발/시연용: 실제 ELM327 스캐너 없이 다음 화면으로 이동한다.
  // TODO: 실제 차량 테스트 시에는 이 버튼을 숨기거나 개발자 설정 메뉴로 이동할 것
  // TODO: 실제 ELM327 연결 성공 시에는 아래 Mock 분기 없이 기존 _connect() 흐름 사용
  Future<void> _enterMockMode() async {
    final prefs     = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final vin       = prefs.getString('vin')        ?? '';

    if (!mounted) return;

    if (authToken.isNotEmpty && vin.isNotEmpty) {
      // 이미 VIN 인증 완료 → HomeScreen으로 바로 이동
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } else {
      // Mock 모드: 임시 VIN/토큰 저장하여 안전점수 화면 진입 가능하게
      await prefs.setString('auth_token', 'MOCK_TOKEN');
      await prefs.setString('vin', 'MOCK-VIN-00000');
      await prefs.setString('car_model', 'Mock 차량 (테스트)');
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _isConnecting = true);

    final success = await _obd.connect(device);

    if (!mounted) return;
    setState(() => _isConnecting = false);

    if (success) {
      if (widget.isReconnect) {
        // 재연결: VIN 인증 이미 완료 → 홈 화면으로 복귀
        Navigator.pop(context);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => VinAuthScreen(obd: _obd),
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연결 실패. 다시 시도해주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('스캐너 연결', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 읽기 전용 안전 안내 카드
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFB923C).withValues(alpha: 0.4)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 20, color: Color(0xFFEA580C)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '본 앱은 표준 OBD-II PID 읽기 전용 모드로만 동작합니다.\n'
                      '제조사 전용 CAN · 제어 · 삭제 · 초기화 명령은 사용하지 않습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFFEA580C),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // BLE 안내 카드
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
              ),
              child: const Row(
                children: [
                  Icon(Icons.bluetooth_searching, size: 20, color: AppColors.primary),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isAutoConnecting ? '이전 기기에 재연결 중...' : '장치 검색 중...',
                      style: const TextStyle(fontSize: 13, color: AppColors.primary),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // 장치 목록
            Expanded(
              child: _scanResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
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
                    )
                  : ListView.builder(
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
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.bluetooth, size: 18, color: AppColors.primary),
                            ),
                            title: Text(name, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(result.device.remoteId.str, style: AppTextStyles.captionHint),
                            trailing: _isConnecting
                                ? const SizedBox(
                                    width: 18, height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                                  )
                                : const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
                            onTap: () => _connect(result.device),
                          ),
                        );
                      },
                    ),
            ),

            // 다시 검색 버튼
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('다시 검색'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Mock 모드 버튼 (개발/시연용)
            // TODO: 실제 차량 테스트(배포) 시에는 이 버튼을 숨기거나 개발자 설정으로 이동
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _isConnecting ? null : _enterMockMode,
                icon: Icon(Icons.science_outlined, size: 15, color: Colors.grey[400]),
                label: Text(
                  '스캐너 없이 테스트하기',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '에뮬레이터/개발 환경 전용 · 실제 OBD 데이터 없음',
                style: TextStyle(fontSize: 10, color: Colors.grey[400]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
