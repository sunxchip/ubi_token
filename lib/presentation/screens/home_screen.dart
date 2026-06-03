import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/obd_datasource.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import 'pid_diagnostic_screen.dart';
import 'driving_score_screen.dart';
import 'onboarding/scanner_connect_screen.dart';
import 'real_drive_screen.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _vin      = '';
  int _lastScore   = 0;

  bool get _isBleConnected => ObdDatasource.connected != null;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _vin       = prefs.getString('vin') ?? '';
      _lastScore = prefs.getInt('last_score') ?? 0;
    });
  }

  Color _scoreColor(int score) {
    if (score >= 90) return AppColors.success;
    if (score >= 70) return AppColors.warning;
    return AppColors.danger;
  }

  String _scoreLabel(int score) {
    if (score >= 90) return '우수한 운전 습관이에요!';
    if (score >= 70) return '조금 더 주의가 필요해요';
    return '운전 습관 개선이 필요해요';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('UBI Token', style: AppTextStyles.h2),
        actions: [
          GestureDetector(
            onTap: _isBleConnected
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ScannerConnectScreen(isReconnect: true),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isBleConnected ? AppColors.successLight : AppColors.warningLight,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _isBleConnected ? AppColors.success : AppColors.warning,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isBleConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 13,
                    color: _isBleConnected ? AppColors.success : AppColors.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isBleConnected ? '연결됨' : '재연결',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _isBleConnected ? AppColors.success : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 20, color: AppColors.textSecondary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 차량 정보 카드
            _VehicleCard(vin: _vin, score: _lastScore, scoreColor: _scoreColor, scoreLabel: _scoreLabel),
            const SizedBox(height: 16),

            // 주요 기능 섹션
            const Text('주요 기능', style: AppTextStyles.h3),
            const SizedBox(height: 10),

            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.95,
              children: [
                _MenuCard(
                  icon: Icons.speed_outlined,
                  label: '대시보드',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen())),
                ),
                _MenuCard(
                  icon: Icons.history_outlined,
                  label: '주행기록',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
                ),
                _MenuCard(
                  icon: Icons.bar_chart_outlined,
                  label: '통계',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen())),
                ),
                _MenuCard(
                  icon: Icons.shield_outlined,
                  label: '안전점수',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DrivingScoreScreen())),
                ),
                _MenuCard(
                  icon: Icons.analytics_outlined,
                  label: 'PID진단',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PidDiagnosticScreen())),
                ),
                _MenuCard(
                  icon: Icons.settings_outlined,
                  label: '설정',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 실차 주행 테스트 — realReadOnlyDrive 모드
            _RealDriveBannerCard(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RealDriveScreen()),
              ),
            ),
            const SizedBox(height: 16),

            // 프로젝트 핵심 소개
            const _ProjectSummaryCard(),
            const SizedBox(height: 16),

            // 백그라운드 상태 pill
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '백그라운드 실행 중 · 시동 감지 대기',
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final String vin;
  final int score;
  final Color Function(int) scoreColor;
  final String Function(int) scoreLabel;

  const _VehicleCard({
    required this.vin,
    required this.score,
    required this.scoreColor,
    required this.scoreLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('내 차량', style: AppTextStyles.h3),
                    const SizedBox(height: 4),
                    Text(
                      vin.isNotEmpty ? vin : '차량 미등록',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: vin.isNotEmpty ? AppColors.successLight : AppColors.warningLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        vin.isNotEmpty ? 'VIN 인증 완료' : '인증 필요',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: vin.isNotEmpty ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.directions_car_outlined, size: 28, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('최근 안전점수', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Spacer(),
              Text(
                score > 0 ? '$score점' : '--',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: score > 0 ? scoreColor(score) : AppColors.textHint,
                ),
              ),
              if (score > 0) ...[
                const SizedBox(width: 6),
                Text(scoreLabel(score), style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── 프로젝트 핵심 소개 카드 ──────────────────────────────────────────────────────
class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          boxShadow: const [
            BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.shield_outlined, size: 17, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'UBI Token 시스템 개요',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.divider),
            const SizedBox(height: 10),
            const _SummaryItem(
              icon: Icons.verified_outlined,
              text: 'VIN 검증 기반 차량 데이터 신뢰성 확보',
            ),
            const _SummaryItem(
              icon: Icons.speed_outlined,
              text: 'OBD-II 표준 PID 기반 실시간 안전운전 점수 산정',
            ),
            const _SummaryItem(
              icon: Icons.science_outlined,
              text: 'Mock / Dry-run 안전 시연 모드 지원',
            ),
            const _SummaryItem(
              icon: Icons.security_outlined,
              text: 'SafeObdCommandValidator — 위험 명령 100% 차단',
            ),
          ],
        ),
      );
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SummaryItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: AppColors.primary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary, height: 1.4),
              ),
            ),
          ],
        ),
      );
}

// ── 실차 주행 테스트 배너 카드 ────────────────────────────────────────────────────
class _RealDriveBannerCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RealDriveBannerCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF9800).withValues(alpha: 0.5)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE0B2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.directions_car, size: 24, color: Color(0xFFE65100)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '실차 주행 테스트',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE65100),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'realReadOnlyDrive',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    '4단계 안전 게이트 · 표준 PID 010C/010D/0111/0104 읽기 전용',
                    style: TextStyle(fontSize: 11, color: Color(0xFF795548)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFFF9800)),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuCard({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
