import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color primary = Color(
    0xFF1565C0,
  ); // активные состояния, главные кнопки
  static const Color accent = Color(0xFF2F80ED); // прогресс, акценты
  static const Color sky = Color(0xFFE6F0FD); // выделение / hover
  static const Color border = Color(0xFFD7E3F4);
  static const Color background = Color(0xFFF4F7FB);
  static const Color surface = Colors.white;
  static const Color text = Color(0xFF0F2A4A);
  static const Color muted = Color(0xFF5E7592);
  static const Color success = Color(0xFF1B8A5A);
  static const Color successBg = Color(0xFFE3F5EC);
  static const Color danger = Color(0xFFC62828);
  static const Color dangerBg = Color(0xFFFDE8E8);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Segoe UI', // системный шрифт Windows
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}

final ButtonStyle filledButtonStyle =
    FilledButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(
      overlayColor: WidgetStatePropertyAll(
        Colors.white.withValues(alpha: 0.12),
      ),
    );

final ButtonStyle outlinedButtonStyle = OutlinedButton.styleFrom(
  foregroundColor: AppColors.primary,
  side: const BorderSide(color: AppColors.border),
  minimumSize: const Size(0, 40),
  padding: const EdgeInsets.symmetric(horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
).copyWith(overlayColor: const WidgetStatePropertyAll(AppColors.sky));

final ButtonStyle outlinedIconButtonStyle = IconButton.styleFrom(
  foregroundColor: AppColors.primary,
  side: const BorderSide(color: AppColors.border),
  minimumSize: const Size(40, 40),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
).copyWith(overlayColor: const WidgetStatePropertyAll(AppColors.sky));

/// Красный вариант [outlinedButtonStyle] для разрушающих действий.
final ButtonStyle dangerOutlinedButtonStyle = outlinedButtonStyle.copyWith(
  foregroundColor: const WidgetStatePropertyAll(AppColors.danger),
  side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFF0C2C2))),
);
