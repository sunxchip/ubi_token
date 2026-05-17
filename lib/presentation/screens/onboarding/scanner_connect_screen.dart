import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../home_screen.dart';
import 'vin_auth_screen.dart';

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
      // VIN 미인증 상태 → HomeScreen으로 이동 후 안전점수 화면에서 Mock 데이터 사용 가능
      // VinAuthScreen은 실제 OBD 연결이 필요하므로 Mock 모드에서는 건너뜀
      // TODO: Mock 전용 VinAuthScreen이 필요하면 MockObdDatasource를 별도 구현할 것
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mock 모드: VIN 미인증 상태입니다. 안전점수 화면에서 Mock 데이터로 테스트 가능합니다.'),
          duration: Duration(seconds: 3),
        ),
      );
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('스캐너 연결'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ELM327 스캐너를 차량에 연결하고\n블루투스를 켜주세요',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (_isAutoConnecting)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('이전 기기에 재연결 중...'),
                ],
              )
            else if (_isScanning)
              const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('장치 검색 중...'),
                ],
              ),
            const SizedBox(height: 16),
            Expanded(
              child: _scanResults.isEmpty
                  ? Center(
                      child: Text(
                        _isScanning ? '검색 중...' : '장치를 찾지 못했습니다',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _scanResults.length,
                      itemBuilder: (context, index) {
                        final result = _scanResults[index];
                        final name = result.device.platformName.isNotEmpty
                            ? result.device.platformName
                            : '알 수 없는 장치';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            title: Text(name),
                            subtitle: Text(result.device.remoteId.str),
                            trailing: _isConnecting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.bluetooth),
                            onTap: () => _connect(result.device),
                          ),
                        );
                      },
                    ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: _isScanning ? null : _startScan,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('다시 검색'),
              ),
            ),
            const SizedBox(height: 12),

            // ── 개발/시연용 Mock 모드 버튼 ──────────────────────────────────
            // TODO: 실제 차량 테스트(배포) 시에는 이 버튼을 숨기거나 개발자 설정으로 이동
            // TODO: 실제 ELM327 연결 성공 시에는 기존 _connect() 흐름이 자동 사용됨
            SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: _isConnecting ? null : _enterMockMode,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[500],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.science_outlined, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Text(
                      '스캐너 없이 테스트하기',
                      style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    ),
                  ],
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
          ],
        ),
      ),
    );
  }
}
