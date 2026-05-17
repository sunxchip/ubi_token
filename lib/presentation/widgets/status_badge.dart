import 'package:flutter/material.dart';
import 'app_colors.dart';

enum BadgeType { success, warning, danger, info, neutral }

class StatusBadge extends StatelessWidget {
  final String label;
  final BadgeType type;
  final IconData? icon;
  const StatusBadge({super.key, required this.label, required this.type, this.icon});

  Color get _bg {
    switch (type) {
      case BadgeType.success: return AppColors.successLight;
      case BadgeType.warning: return AppColors.warningLight;
      case BadgeType.danger:  return AppColors.dangerLight;
      case BadgeType.info:    return AppColors.primaryLight;
      case BadgeType.neutral: return const Color(0xFFF3F4F6);
    }
  }
  Color get _fg {
    switch (type) {
      case BadgeType.success: return AppColors.success;
      case BadgeType.warning: return AppColors.warning;
      case BadgeType.danger:  return AppColors.danger;
      case BadgeType.info:    return AppColors.primary;
      case BadgeType.neutral: return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(4)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null) ...[Icon(icon, size: 11, color: _fg), const SizedBox(width: 3)],
      Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _fg)),
    ]),
  );
}
