import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/datasources/api_datasource.dart';
import '../../../data/datasources/car_info_datasource.dart';
import '../../../core/utils/app_mode_controller.dart';
import '../../../core/enums/obd_connection_mode.dart';
import 'scanner_connect_screen.dart';
import '../home_screen.dart';
import '../../widgets/app_colors.dart';
import '../../widgets/app_text_styles.dart';

class VinAuthScreen extends StatefulWidget {
  const VinAuthScreen({super.key});

  @override
  State<VinAuthScreen> createState() => _VinAuthScreenState();
}

class _VinAuthScreenState extends State<VinAuthScreen> {
  final _api          = ApiDatasource();
  final _carInfoDs    = CarInfoDatasource();
  final _vinController = TextEditingController();
  final _vinFocus      = FocusNode();

  // ── 저장된 인증 정보 ──────────────────────────────────────────────────
  String _savedVin       = '';
  String _savedCarModel  = '';
  bool   _alreadyVerified = false;

  // ── UI 상태 ────────────────────────────────────────────────────────
  bool _isLoading     = false;
  bool _isDecoding    = false;
  bool _isVerifying   = false;

  String   _errorMsg  = '';
  CarInfo? _carInfo;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _vinController.dispose();
    _vinFocus.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token') ?? '';
    final vin   = prefs.getString('vin')         ?? '';
    final model = prefs.getString('car_model')   ?? '';

    if (!mounted) return;
    setState(() {
      _savedVin       = vin;
      _savedCarModel  = model;
      _alreadyVerified = token.isNotEmpty && vin.isNotEmpty;
      _isLoading      = false;
    });
  }

  // ── VIN 입력 → NHTSA 디코딩 → 서버 인증 ──────────────────────────
  Future<void> _decodeAndVerify() async {
    final vin = _vinController.text.trim().toUpperCase();
    if (vin.length != 17) {
      setState(() => _errorMsg = 'VIN은 17자리여야 합니다 (현재 ${vin.length}자)');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _errorMsg = ''; _carInfo = null; _isDecoding = true; });

    // NHTSA 차량 정보 조회
    try {
      final info = await _carInfoDs.decodeVin(vin);
      if (!mounted) return;
      setState(() { _carInfo = info; _isDecoding = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDecoding = false;
        _errorMsg   = '차량 정보 조회 실패: ${e.toString().replaceFirst('Exception: ', '')}';
      });
    }

    // 서버 VIN 인증
    await _verifyVin(vin);
  }

  Future<void> _verifyVin(String vin) async {
    setState(() { _isVerifying = true; _errorMsg = ''; });

    final prefs  = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';

    if (userId.isEmpty) {
      setState(() {
        _isVerifying = false;
        _errorMsg    = '로그인 정보가 없습니다. 다시 로그인해주세요.';
      });
      return;
    }

    final result = await _api.vinVerify(userId: userId, vin: vin);
    if (!mounted) return;
    setState(() => _isVerifying = false);

    if (result == null || result.containsKey('error')) {
      setState(() => _errorMsg = result?['error'] ?? '서버 오류가 발생했습니다');
      return;
    }

    await prefs.setString('auth_token', result['token'] ?? '');
    await prefs.setString('vin', result['vin']  ?? vin);
    if (_carInfo != null) {
      await prefs.setString('car_model',
          '${_carInfo!.make} ${_carInfo!.model}'.trim());
      await prefs.setString('car_year', _carInfo!.modelYear);
    }

    if (!mounted) return;
    _goToScanner();
  }

  // ── 체험 모드 진입 ────────────────────────────────────────────────
  Future<void> _enterDemoMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', 'DEMO_TOKEN');
    await prefs.setString('vin',        'DEMO-VIN-00000000');
    await prefs.setString('car_model',  '체험 차량');
    AppModeController().setMode(ObdConnectionMode.mock);
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  void _goToScanner() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ScannerConnectScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('차량 인증', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _alreadyVerified
              ? _buildAlreadyVerified()
              : _buildInputForm(),
    );
  }

  // ── 이미 인증 완료된 경우 ─────────────────────────────────────────
  Widget _buildAlreadyVerified() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppColors.successLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_rounded,
                size: 36, color: AppColors.success),
          ),
          const SizedBox(height: 20),
          const Text('차량 인증 완료', style: AppTextStyles.h2),
          const SizedBox(height: 6),
          const Text('등록된 차량으로 계속 이용합니다',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 28),

          // VIN 카드
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('등록 차량', style: AppTextStyles.caption),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.directions_car_outlined,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_savedCarModel.isNotEmpty)
                            Text(_savedCarModel,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                          Text(
                            _savedVin,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.8),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text('인증 완료',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.success)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.bluetooth_searching,
                  color: Colors.white, size: 18),
              label: const Text('스캐너 연결로 이동',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              onPressed: _goToScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() {
              _alreadyVerified = false;
              _savedVin = '';
            }),
            child: const Text('다른 차량으로 재인증',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ── VIN 입력 폼 ───────────────────────────────────────────────────
  Widget _buildInputForm() {
    final isBusy = _isDecoding || _isVerifying;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20,
          MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 안내
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '차량 등록증 또는 계기판 하단에서 17자리 차대번호(VIN)를 확인할 수 있습니다.',
                    style: TextStyle(fontSize: 13, color: AppColors.primary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // VIN 입력 필드
          const Text('차대번호(VIN) 입력', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          TextFormField(
            controller: _vinController,
            focusNode: _vinFocus,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(17),
            ],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => isBusy ? null : _decodeAndVerify(),
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5),
            decoration: InputDecoration(
              hintText: 'KMHXX00X0XX000000',
              hintStyle: const TextStyle(
                  letterSpacing: 1.2,
                  color: AppColors.textHint,
                  fontWeight: FontWeight.normal),
              prefixIcon: const Icon(Icons.credit_card_outlined, size: 20),
              suffixText: '${_vinController.text.length}/17',
              suffixStyle: const TextStyle(
                  fontSize: 12, color: AppColors.textHint),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          const Text(
            '영문과 숫자만 입력 가능합니다 · 자동으로 대문자 변환',
            style: TextStyle(fontSize: 11, color: AppColors.textHint),
          ),

          // 에러
          if (_errorMsg.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMsg,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          // 차량 정보 카드 (NHTSA 디코딩 결과)
          if (_carInfo != null) ...[
            const SizedBox(height: 12),
            _buildCarInfoCard(_carInfo!),
          ],

          const SizedBox(height: 20),

          // 인증 버튼
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (isBusy || _vinController.text.trim().length != 17)
                  ? null
                  : _decodeAndVerify,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: isBusy
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isDecoding ? '차량 정보 조회 중...' : '인증 중...',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    )
                  : const Text(
                      '차량 인증하기',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // 체험 모드 진입 (하단 subtle)
          const Divider(color: AppColors.divider),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _enterDemoMode,
              child: const Text(
                '스캐너와 차량 없이 체험하기',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarInfoCard(CarInfo info) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.directions_car_outlined,
                  size: 15, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text('조회된 차량 정보', style: AppTextStyles.caption),
            ],
          ),
          const SizedBox(height: 10),
          if (info.make.isNotEmpty || info.model.isNotEmpty)
            _Row('차명', '${info.make} ${info.model}'.trim()),
          if (info.modelYear.isNotEmpty) _Row('연식', '${info.modelYear}년'),
          if (info.bodyClass.isNotEmpty) _Row('차종', info.bodyClass),
          if (info.fuelType.isNotEmpty) _Row('연료', info.fuelType),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
                width: 50,
                child: Text(label, style: AppTextStyles.caption)),
            Expanded(child: Text(value, style: AppTextStyles.body)),
          ],
        ),
      );
}
