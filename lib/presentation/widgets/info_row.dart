import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;
  const InfoRow({super.key, required this.label, required this.value, this.showDivider = true});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Text(label, style: AppTextStyles.caption),
          const Spacer(),
          Text(value, style: AppTextStyles.label),
        ]),
      ),
      if (showDivider) const Divider(height: 1, color: AppColors.divider),
    ],
  );
}
