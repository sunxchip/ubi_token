import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();
  static const h1 = TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
  static const h2 = TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const h3 = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  static const body = TextStyle(fontSize: 14, color: AppColors.textPrimary);
  static const bodySecondary = TextStyle(fontSize: 14, color: AppColors.textSecondary);
  static const caption = TextStyle(fontSize: 12, color: AppColors.textSecondary);
  static const captionHint = TextStyle(fontSize: 12, color: AppColors.textHint);
  static const label = TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary);
}
