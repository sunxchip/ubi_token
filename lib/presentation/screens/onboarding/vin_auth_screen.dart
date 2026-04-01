import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../home_screen.dart';

class VinAuthScreen extends StatefulWidget {
  final ObdDatasource obd;
  const VinAuthScreen({super.key, required this.obd});

  @override
  State<VinAuthScreen> createState() => _VinAuthScreenState();
}

class _VinAuthScreenState extends State<VinAuthScreen> {
  String _vin       = '';
  bool _isLoading   = true;
  bool _isVerifying = false;
  String _status    = 'VIN 추출 중...';

  @override
  void initState() {
    super.initState();
    _extractVin();
  }

  Future<void> _extractVin() async {
    setState(() {
      _isLoading = true;
      _status    = 'OBD-II에서 VIN 읽는 중...';
    });

    final vin = await widget.obd.getVin();

    if (!mounted) return;
    setState(() {
      _vin       = vin;
      _isLoading = false;
      _status    = vin.isNotEmpty ? 'VIN 추출 완료' : 'VIN을 읽지 못했습니다';
    });
  }

  Future<void> _verifyVin() async {
    if (_vin.isEmpty) return;
    setState(() => _isVerifying = true);

    // TODO: 서버 VIN 검증 연동
    // 지금은 로컬 저장으로 임시 처리
    await Future.delayed(const Duration(seconds: 1));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vin', _vin);
    await prefs.setString('auth_token', 'local_token_${_vin}');

    if (!mounted) return;
    setState(() => _isVerifying = false);

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('차량 인증'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '차대번호(VIN)로 차량을 인증합니다',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'VIN (차대번호)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  _isLoading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : Text(
                    _vin.isNotEmpty ? _vin : '읽기 실패',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _vin.isNotEmpty
                          ? const Color(0xFF1B3A5C)
                          : Colors.red,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: TextStyle(
                fontSize: 13,
                color: _vin.isNotEmpty ? Colors.green : Colors.grey,
              ),
            ),
            const Spacer(),
            if (_vin.isEmpty && !_isLoading)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: _extractVin,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('다시 시도'),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_vin.isNotEmpty && !_isVerifying) ? _verifyVin : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B3A5C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isVerifying
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  '인증하기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}