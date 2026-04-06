import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../../../data/datasources/api_datasource.dart';
import '../home_screen.dart';

class VinAuthScreen extends StatefulWidget {
  final ObdDatasource obd;
  const VinAuthScreen({super.key, required this.obd});

  @override
  State<VinAuthScreen> createState() => _VinAuthScreenState();
}

class _VinAuthScreenState extends State<VinAuthScreen> {
  final _api      = ApiDatasource();
  String _vin     = '';
  bool _isLoading = true;
  bool _isVerifying = false;
  String _status  = 'OBD-II에서 VIN 읽는 중...';
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _extractVin();
  }

  Future<void> _extractVin() async {
    setState(() {
      _isLoading = true;
      _status    = 'OBD-II에서 VIN 읽는 중...';
      _errorMsg  = '';
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
    setState(() {
      _isVerifying = true;
      _errorMsg    = '';
    });

    final prefs  = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';

    if (userId.isEmpty) {
      setState(() {
        _isVerifying = false;
        _errorMsg    = '로그인 정보가 없습니다. 다시 로그인해주세요.';
      });
      return;
    }

    // 서버에 VIN 인증 요청
    final result = await _api.vinVerify(
      userId: userId,
      vin: _vin,
    );

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result == null || result.containsKey('error')) {
      setState(() => _errorMsg = result?['error'] ?? '서버 오류가 발생했습니다');
      return;
    }

    // 토큰 로컬 저장
    await prefs.setString('auth_token', result['token']);
    await prefs.setString('vin', result['vin']);

    if (!mounted) return;

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

            // VIN 표시 카드
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
                      fontSize: 15,
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

            const SizedBox(height: 12),

            // 상태 메시지
            Row(
              children: [
                Icon(
                  _vin.isNotEmpty
                      ? Icons.check_circle
                      : Icons.info_outline,
                  size: 16,
                  color: _vin.isNotEmpty ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  _status,
                  style: TextStyle(
                    fontSize: 13,
                    color: _vin.isNotEmpty ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),

            // 에러 메시지
            if (_errorMsg.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            // 다시 시도 버튼
            if (_vin.isEmpty && !_isLoading)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
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
              ),

            // 인증하기 버튼
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed:
                (_vin.isNotEmpty && !_isVerifying) ? _verifyVin : null,
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