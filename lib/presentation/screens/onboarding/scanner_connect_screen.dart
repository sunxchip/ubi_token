import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../data/datasources/obd_datasource.dart';
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
          ],
        ),
      ),
    );
  }
}
