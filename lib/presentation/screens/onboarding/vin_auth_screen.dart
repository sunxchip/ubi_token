import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/obd_datasource.dart';
import '../../../data/datasources/api_datasource.dart';
import '../../../data/datasources/car_info_datasource.dart';
import '../home_screen.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_text_styles.dart';

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('차량 인증', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 텍스트
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OBD 스캐너에서 읽은 차대번호로 차량 정보를 확인합니다',
                      style: TextStyle(fontSize: 13, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // VIN 카드
            _buildVinCard(),
            const SizedBox(height: 12),

            // 차량 정보 카드
            if (_carInfoResult != null) ...[
              _buildCarInfoCard(_carInfoResult!),
              const SizedBox(height: 12),
            ],

            // 에러 메시지들
            if (_vinError.isNotEmpty) _ErrorBox(message: _vinError),
            if (_decodeError.isNotEmpty) _ErrorBox(message: '차량 정보 조회 실패: $_decodeError'),
            if (_verifyError.isNotEmpty) _ErrorBox(message: _verifyError),

            const SizedBox(height: 8),

            // 다시 시도 버튼
            if (_vinError.isNotEmpty || (_vin.isEmpty && !_isLoadingVin))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _readAndDecodeVin,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('다시 시도'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ),

            // 인증하기 버튼
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canVerify ? _verifyVin : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.border,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isVerifying
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        '인증하기',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVinCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card_outlined, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              const Text('차대번호 (VIN)', style: AppTextStyles.caption),
              const Spacer(),
              if (_isLoadingVin)
                const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _isLoadingVin
              ? const Text('OBD에서 읽는 중...', style: AppTextStyles.bodySecondary)
              : _vin.isNotEmpty
                  ? Text(
                      _vin,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 1.2,
                      ),
                    )
                  : const Text('읽기 실패', style: TextStyle(color: AppColors.danger, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCarInfoCard(CarInfo info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_car_outlined, size: 15, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text('차량 정보', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 10),
          _isDecodingVin
              ? const Row(
                  children: [
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                    SizedBox(width: 10),
                    Text('차량 정보 조회 중...', style: AppTextStyles.bodySecondary),
                  ],
                )
              : Column(
                  children: [
                    if (info.make.isNotEmpty || info.model.isNotEmpty)
                      _InfoRowItem('차명', '${info.make} ${info.model}'.trim()),
                    if (info.modelYear.isNotEmpty)
                      _InfoRowItem('연식', '${info.modelYear}년'),
                    if (info.bodyClass.isNotEmpty)
                      _InfoRowItem('차종', info.bodyClass),
                    if (info.fuelType.isNotEmpty)
                      _InfoRowItem('연료', info.fuelType),
                    if (info.plantCountry.isNotEmpty)
                      _InfoRowItem('생산국', info.plantCountry, showDivider: false),
                  ],
                ),
        ],
      ),
    );
  }
}

class _InfoRowItem extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;
  const _InfoRowItem(this.label, this.value, {this.showDivider = true});

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 60,
                  child: Text(label, style: AppTextStyles.caption),
                ),
                Expanded(
                  child: Text(value, style: AppTextStyles.body),
                ),
              ],
            ),
          ),
          if (showDivider) const Divider(height: 1, color: AppColors.divider),
        ],
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
            color: AppColors.dangerLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(message, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ),
            ],
          ),
        ),
      );
}
