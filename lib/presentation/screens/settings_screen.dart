import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'onboarding/signup_screen.dart';
import 'pid_diagnostic_screen.dart';
import 'real_drive_screen.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_text_styles.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool   _eventAlert  = true;
  bool   _vibration   = true;
  String _vin         = '';
  String _carModel    = '';
  String _email       = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _eventAlert = prefs.getBool('event_alert') ?? true;
      _vibration  = prefs.getBool('vibration')   ?? true;
      _vin        = prefs.getString('vin')        ?? '';
      _carModel   = prefs.getString('car_model')  ?? '';
      _email      = prefs.getString('email')      ?? '';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('event_alert', _eventAlert);
    await prefs.setBool('vibration', _vibration);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('로그아웃', style: AppTextStyles.h3),
        content: const Text('로그아웃하시겠습니까?',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소',
                  style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('로그아웃',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SignupScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('설정', style: AppTextStyles.h2),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 계정 정보 ─────────────────────────────────────
          _SectionLabel('계정'),
          const SizedBox(height: 6),
          _SettingsGroup(
            children: [
              if (_email.isNotEmpty)
                _InfoTile(
                  icon: Icons.person_outline,
                  label: '이메일',
                  value: _email,
                ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 차량 정보 ─────────────────────────────────────
          _SectionLabel('차량 정보'),
          const SizedBox(height: 6),
          _SettingsGroup(
            children: [
              _InfoTile(
                icon: Icons.directions_car_outlined,
                label: '차량',
                value: _carModel.isNotEmpty ? _carModel : '등록된 차량 없음',
                valueColor: _carModel.isNotEmpty
                    ? AppColors.textPrimary
                    : AppColors.textHint,
              ),
              if (_vin.isNotEmpty && !_vin.startsWith('DEMO')) ...[
                const Divider(height: 1, indent: 52, color: AppColors.divider),
                _InfoTile(
                  icon: Icons.credit_card_outlined,
                  label: 'VIN',
                  value: _vin,
                ),
              ],
            ],
          ),

          const SizedBox(height: 20),

          // ── 알림 설정 ─────────────────────────────────────
          _SectionLabel('알림'),
          const SizedBox(height: 6),
          _SettingsGroup(
            children: [
              _SwitchTile(
                icon: Icons.notifications_outlined,
                label: '이벤트 알림',
                sub: '급가속·과속 감지 시 알림',
                value: _eventAlert,
                onChanged: (v) {
                  setState(() => _eventAlert = v);
                  _saveSettings();
                },
              ),
              const Divider(height: 1, indent: 52, color: AppColors.divider),
              _SwitchTile(
                icon: Icons.vibration_outlined,
                label: '진동',
                sub: '이벤트 발생 시 진동',
                value: _vibration,
                onChanged: (v) {
                  setState(() => _vibration = v);
                  _saveSettings();
                },
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 고급 도구 (발표/진단용) ───────────────────────
          _SectionLabel('고급 도구'),
          const SizedBox(height: 6),
          _SettingsGroup(
            children: [
              _ActionTile(
                icon: Icons.analytics_outlined,
                label: 'PID 진단',
                sub: 'OBD 명령 검증 및 차량 데이터 확인',
                color: AppColors.textPrimary,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PidDiagnosticScreen()),
                ),
              ),
              const Divider(height: 1, indent: 52, color: AppColors.divider),
              _ActionTile(
                icon: Icons.directions_car_outlined,
                label: '실차 주행 테스트',
                sub: '4단계 안전 게이트 · 표준 PID 읽기 전용',
                color: const Color(0xFFE65100),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RealDriveScreen()),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 계정 관리 ─────────────────────────────────────
          _SectionLabel('계정 관리'),
          const SizedBox(height: 6),
          _SettingsGroup(
            children: [
              _ActionTile(
                icon: Icons.logout_outlined,
                label: '로그아웃',
                color: AppColors.danger,
                onTap: _logout,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── 앱 정보 ───────────────────────────────────────
          _SectionLabel('앱 정보'),
          const SizedBox(height: 6),
          _SettingsGroup(
            children: [
              const _InfoTile(
                icon: Icons.info_outline,
                label: '버전',
                value: '1.0.0',
              ),
              const Divider(height: 1, indent: 52, color: AppColors.divider),
              const _InfoTile(
                icon: Icons.shield_outlined,
                label: '보안',
                value: '표준 OBD-II PID 읽기 전용',
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      );
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
          ],
        ),
        child: Column(children: children),
      );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor = AppColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTextStyles.body)),
            Flexible(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  color: valueColor,
                  fontWeight: FontWeight.w500,
                  letterSpacing: value.length > 10 ? 0.5 : 0,
                ),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.body),
                  Text(sub, style: AppTextStyles.captionHint),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.sub,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            color: color,
                            fontWeight: FontWeight.w500)),
                    if (sub != null)
                      Text(sub!,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textHint)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      );
}
