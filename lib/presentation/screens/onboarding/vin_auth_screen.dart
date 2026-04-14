import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../../../data/datasources/api_datasource.dart';
import '../../../data/datasources/car_info_datasource.dart';
import '../home_screen.dart';

class VinAuthScreen extends StatefulWidget {
  final ObdDatasource obd;
  const VinAuthScreen({super.key, required this.obd});

  @override
  State<VinAuthScreen> createState() => _VinAuthScreenState();
}

class _VinAuthScreenState extends State<VinAuthScreen> {
  final _api     = ApiDatasource();
  final _carInfo = CarInfoDatasource();

  String   _vin          = '';
  CarInfo? _carInfoResult;

  bool   _isLoadingVin  = true;
  bool   _isDecodingVin = false;
  bool   _isVerifying   = false;

  String _vinError    = '';
  String _decodeError = '';
  String _verifyError = '';

  @override
  void initState() {
    super.initState();
    _readAndDecodeVin();
  }

  // ── OBD VIN 읽기 → NHTSA 자동 조회 ──────────────────
  Future<void> _readAndDecodeVin() async {
    setState(() {
      _isLoadingVin  = true;
      _isDecodingVin = false;
      _vinError      = '';
      _decodeError   = '';
      _carInfoResult = null;
    });

    // 1단계: OBD/CAN에서 VIN 읽기
    try {
      final vin = await widget.obd.getVin();
      if (!mounted) return;
      if (vin.isEmpty) {
        setState(() {
          _isLoadingVin = false;
          _vinError     = 'OBD에서 VIN을 읽지 못했습니다. 다시 시도해주세요.';
        });
        return;
      }
      setState(() {
        _vin          = vin;
        _isLoadingVin = false;
        _isDecodingVin = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingVin = false;
        _vinError     = '장치 통신 오류: $e';
      });
      return;
    }

    // 2단계: VIN으로 차량 정보 조회
    try {
      final info = await _carInfo.decodeVin(_vin);
      if (!mounted) return;
      setState(() {
        _carInfoResult = info;
        _isDecodingVin = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDecodingVin = false;
        _decodeError   = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── 서버 VIN 인증 ────────────────────────────────────
  Future<void> _verifyVin() async {
    setState(() {
      _isVerifying = true;
      _verifyError = '';
    });

    final prefs  = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';

    if (userId.isEmpty) {
      setState(() {
        _isVerifying = false;
        _verifyError = '로그인 정보가 없습니다. 다시 로그인해주세요.';
      });
      return;
    }

    final result = await _api.vinVerify(userId: userId, vin: _vin);

    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result == null || result.containsKey('error')) {
      setState(() => _verifyError = result?['error'] ?? '서버 오류가 발생했습니다');
      return;
    }

    await prefs.setString('auth_token', result['token']);
    await prefs.setString('vin', result['vin']);
    if (_carInfoResult != null) {
      await prefs.setString('car_model',
          '${_carInfoResult!.make} ${_carInfoResult!.model}');
      await prefs.setString('car_year', _carInfoResult!.modelYear);
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  bool get _canVerify =>
      _vin.isNotEmpty && !_isLoadingVin && !_isDecodingVin && !_isVerifying;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('차량 인증'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OBD 스캐너에서 읽은 차대번호로\n차량 정보를 확인합니다',
              style: TextStyle(fontSize: 15, color: Colors.grey),
            ),
            const SizedBox(height: 28),

            // ── VIN 카드 ──────────────────────────────
            _buildVinCard(),
            const SizedBox(height: 16),

            // ── 차량 정보 카드 ─────────────────────────
            if (_carInfoResult != null) ...[
              _buildCarInfoCard(_carInfoResult!),
              const SizedBox(height: 16),
            ],

            // ── 에러 메시지들 ─────────────────────────
            if (_vinError.isNotEmpty) _ErrorBox(message: _vinError),
            if (_decodeError.isNotEmpty) _ErrorBox(message: '차량 정보 조회 실패: $_decodeError'),
            if (_verifyError.isNotEmpty) _ErrorBox(message: _verifyError),

            const SizedBox(height: 8),

            // ── 다시 시도 버튼 ─────────────────────────
            if (_vinError.isNotEmpty || (_vin.isEmpty && !_isLoadingVin))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _readAndDecodeVin,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('다시 시도'),
                  ),
                ),
              ),

            // ── 인증하기 버튼 ─────────────────────────
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _canVerify ? _verifyVin : null,
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

  Widget _buildVinCard() {
    return _InfoCard(
      title: '차대번호 (VIN)',
      child: _isLoadingVin
          ? const _LoadingRow(label: 'OBD에서 읽는 중...')
          : _vin.isNotEmpty
              ? Text(
                  _vin,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B3A5C),
                    letterSpacing: 1.5,
                  ),
                )
              : const Text(
                  '읽기 실패',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
    );
  }

  Widget _buildCarInfoCard(CarInfo info) {
    return _InfoCard(
      title: '차량 정보',
      child: _isDecodingVin
          ? const _LoadingRow(label: '차량 정보 조회 중...')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (info.make.isNotEmpty || info.model.isNotEmpty)
                  _InfoRow(
                    '차명',
                    '${info.make} ${info.model}'.trim(),
                  ),
                if (info.modelYear.isNotEmpty)
                  _InfoRow('연식', '${info.modelYear}년'),
                if (info.bodyClass.isNotEmpty)
                  _InfoRow('차종', info.bodyClass),
                if (info.fuelType.isNotEmpty)
                  _InfoRow('연료', info.fuelType),
                if (info.plantCountry.isNotEmpty)
                  _InfoRow('생산국', info.plantCountry),
              ],
            ),
    );
  }
}

// ── 공용 위젯 ──────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _InfoCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      );
}

class _LoadingRow extends StatelessWidget {
  final String label;
  const _LoadingRow({required this.label});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
            ),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
}
