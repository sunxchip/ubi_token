import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
    ),
    child: onTap != null
        ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12),
            child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child))
        : Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
  );
}
