import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/obd_datasource.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'stats_screen.dart';
import 'settings_screen.dart';
import 'pid_diagnostic_screen.dart';
import 'onboarding/scanner_connect_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // 상단 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '안녕하세요',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1B3A5C),
                        ),
                      ),
                      Text(
                        '오늘도 안전 운전하세요',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _isBleConnected
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const ScannerConnectScreen(
                                  isReconnect: true,
                                ),
                              ),
                            );
                            // 재연결 후 UI 갱신
                            if (mounted) setState(() {});
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _isBleConnected
                            ? Colors.green[50]
                            : Colors.orange[50],
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: _isBleConnected
                              ? Colors.green
                              : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isBleConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                            size: 14,
                            color: _isBleConnected
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isBleConnected ? 'BLE 연결됨' : '탭하여 재연결',
                            style: TextStyle(
                              fontSize: 11,
                              color: _isBleConnected
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 최근 주행 점수 카드
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Text(
                      '최근 주행 점수',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lastScore > 0 ? '$_lastScore' : '--',
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        color: _scoreColor(_lastScore),
                      ),
                    ),
                    if (_lastScore > 0)
                      Text(
                        _scoreLabel(_lastScore),
                        style: TextStyle(
                          fontSize: 13,
                          color: _scoreColor(_lastScore),
                        ),
                      ),
                    if (_lastScore == 0)
                      Text(
                        '아직 주행 기록이 없습니다',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[400],
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 버튼 카드 2x2 그리드
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.15,
                children: [
                  _MenuCard(
                    icon: Icons.list_alt_rounded,
                    iconColor: const Color(0xFF2563EB),
                    iconBg: const Color(0xFFEFF6FF),
                    label: '주행 이력',
                    sub: '전체 기록 보기',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HistoryScreen()),
                    ),
                  ),
                  _MenuCard(
                    icon: Icons.bar_chart_rounded,
                    iconColor: const Color(0xFF1D9E75),
                    iconBg: const Color(0xFFE1F5EE),
                    label: '통계',
                    sub: '주간·월간 분석',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const StatsScreen()),
                    ),
                  ),
                  _MenuCard(
                    icon: Icons.speed_rounded,
                    iconColor: const Color(0xFFEF9F27),
                    iconBg: const Color(0xFFFAEEDA),
                    label: '대시보드',
                    sub: '수동으로 열기',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DashboardScreen()),
                    ),
                  ),
                  _MenuCard(
                    icon: Icons.settings_rounded,
                    iconColor: const Color(0xFF888780),
                    iconBg: const Color(0xFFF1EFE8),
                    label: '설정',
                    sub: '알림·차량 관리',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SettingsScreen()),
                    ),
                  ),
                  _MenuCard(
                    icon: Icons.developer_mode_rounded,
                    iconColor: const Color(0xFF0EA5E9),
                    iconBg: const Color(0xFFE0F2FE),
                    label: 'PID 진단',
                    sub: '실차 검증용',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const PidDiagnosticScreen()),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 백그라운드 상태 pill
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '백그라운드 실행 중 · 시동 감지 대기',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

  Color _scoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return const Color(0xFFEF9F27);
    return Colors.red;
  }

  String _scoreLabel(int score) {
    if (score >= 90) return '우수한 운전 습관이에요!';
    if (score >= 70) return '조금 더 주의가 필요해요';
    return '운전 습관 개선이 필요해요';
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String sub;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1B3A5C),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}