import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/obd_datasource.dart';
import '../../core/enums/obd_connection_mode.dart';
import '../../core/utils/app_mode_controller.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import 'driving_score_screen.dart';
import 'onboarding/scanner_connect_screen.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _vin       = '';
  String _carModel  = '';
  String _email     = '';
  int    _lastScore = 0;

  bool get _isBleConnected => ObdDatasource.connected != null;
  bool get _isMockMode     =>
      AppModeController().mode == ObdConnectionMode.mock;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vin       = prefs.getString('vin')        ?? '';
      _carModel  = prefs.getString('car_model')  ?? '';
      _email     = prefs.getString('email')      ?? '';
      _lastScore = prefs.getInt('last_score')    ?? 0;
    });
  }

  Color _scoreColor(int score) {
    if (score >= 90) return AppColors.success;
    if (score >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  String _scoreGrade(int score) {
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    return 'D';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF1B3A5C),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Center(
                child: Text('U',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Ubi-Token', style: AppTextStyles.h2),
          ],
        ),
        actions: [
          // BLE 상태 pill
          GestureDetector(
            onTap: _isBleConnected || _isMockMode
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const ScannerConnectScreen(isReconnect: true),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: (_isBleConnected || _isMockMode)
                    ? AppColors.successLight
                    : AppColors.warningLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (_isBleConnected || _isMockMode)
                      ? AppColors.success
                      : AppColors.warning,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isMockMode
                        ? Icons.science_outlined
                        : _isBleConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_disabled,
                    size: 12,
                    color: (_isBleConnected || _isMockMode)
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isMockMode
                        ? '체험 모드'
                        : _isBleConnected
                            ? '연결됨'
                            : '재연결',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: (_isBleConnected || _isMockMode)
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                size: 20, color: AppColors.textSecondary),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
              if (mounted) _loadData();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 차량 정보 카드 ──────────────────────────────────
              _VehicleCard(
                vin: _vin,
                carModel: _carModel,
                email: _email,
                score: _lastScore,
                scoreColor: _scoreColor,
                scoreGrade: _scoreGrade,
                isMockMode: _isMockMode,
              ),
              const SizedBox(height: 20),

              // ── 주요 기능 3개 ───────────────────────────────────
              const Text('주요 기능', style: AppTextStyles.h3),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _FeatureCard(
                      icon: Icons.speed_outlined,
                      label: '대시보드',
                      description: '실시간 차량 상태',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const DashboardScreen())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FeatureCard(
                      icon: Icons.history_outlined,
                      label: '주행기록',
                      description: '지난 주행 이력',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const HistoryScreen())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FeatureCard(
                      icon: Icons.bar_chart_outlined,
                      label: '통계',
                      description: '운전 패턴 분석',
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const StatsScreen())),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── 안전점수 배너 ───────────────────────────────────
              _ScoreBanner(
                score: _lastScore,
                scoreColor: _scoreColor,
                scoreGrade: _scoreGrade,
              ),
              const SizedBox(height: 24),

              // ── 체험 모드 (하단 서브 섹션) ──────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('모의 데이터 체험',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '스캐너 없이 안전점수 계산을 체험해볼 수 있습니다',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textHint),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            AppModeController()
                                .setMode(ObdConnectionMode.mock);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const DrivingScoreScreen()),
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            backgroundColor: AppColors.primaryLight,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text(
                            '체험하기',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 차량 정보 카드 ────────────────────────────────────────────────────────────
class _VehicleCard extends StatelessWidget {
  final String vin;
  final String carModel;
  final String email;
  final int score;
  final Color Function(int) scoreColor;
  final String Function(int) scoreGrade;
  final bool isMockMode;

  const _VehicleCard({
    required this.vin,
    required this.carModel,
    required this.email,
    required this.score,
    required this.scoreColor,
    required this.scoreGrade,
    required this.isMockMode,
  });

  @override
  Widget build(BuildContext context) {
    final hasVin = vin.isNotEmpty && !vin.startsWith('DEMO');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.directions_car_outlined,
                    size: 26, color: AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      carModel.isNotEmpty && !carModel.contains('체험')
                          ? carModel
                          : isMockMode
                              ? '체험 모드'
                              : '등록된 차량',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    if (hasVin)
                      Text(
                        vin,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.6),
                      )
                    else
                      Text(
                        email.isNotEmpty ? email : '차량 미등록',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
              if (isMockMode)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('체험',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                )
              else if (hasVin)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('인증 완료',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success)),
                ),
            ],
          ),
          if (score > 0) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('최근 안전점수',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scoreColor(score).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${score}점',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: scoreColor(score)),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        scoreGrade(score),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: scoreColor(score)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── 주요 기능 카드 ────────────────────────────────────────────────────────────
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 안전점수 배너 ─────────────────────────────────────────────────────────────
class _ScoreBanner extends StatelessWidget {
  final int score;
  final Color Function(int) scoreColor;
  final String Function(int) scoreGrade;

  const _ScoreBanner({
    required this.score,
    required this.scoreColor,
    required this.scoreGrade,
  });

  @override
  Widget build(BuildContext context) {
    if (score == 0) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.shield_outlined, size: 20, color: AppColors.textHint),
            SizedBox(width: 10),
            Text('아직 주행 기록이 없습니다',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    final color = scoreColor(score);
    final grade = scoreGrade(score);
    final message = score >= 90
        ? '훌륭한 안전 운전 습관을 유지하고 있습니다'
        : score >= 70
            ? '안전 운전을 위해 조금 더 주의해주세요'
            : '운전 습관 개선이 필요합니다';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                grade,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('최근 안전점수 ',
                        style: TextStyle(
                            fontSize: 12, color: color)),
                    Text('${score}점',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(message,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
