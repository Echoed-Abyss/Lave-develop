import 'package:flutter/material.dart';

/// 玻璃（Glassmorphism）主题。
///
/// 设计约束（移动端玻璃效果最容易做过头的地方）：
/// 1. **模糊半径不能太大**：`BackdropFilter` 的 `sigma` 每提高一档，
///    GPU 成本显著上升，在低端安卓机上会直接掉帧。这里统一取 18，
///    并对列表项用更低的 8；
/// 2. **必须有纯色兜底**：玻璃层依赖背景有内容才能显出质感，
///    因此 Scaffold 背景是一层渐变，而不是纯白 / 纯黑；
/// 3. **对比度优先于美观**：文字颜色不透明度不低于 0.72，
///    否则在浅色渐变上会看不清。
class GlassTheme {
  GlassTheme._();

  /// 背景渐变（浅色）。
  static const LinearGradient lightBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEAF3FF), Color(0xFFF6F0FF), Color(0xFFEFFAF6)],
  );

  /// 背景渐变（深色）。
  static const LinearGradient darkBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B1020), Color(0xFF161230), Color(0xFF0D1A1F)],
  );

  /// 品牌主色。
  static const Color brand = Color(0xFF12B7F5);

  /// 玻璃层的基础模糊强度。
  static const double blurSigma = 18;

  /// 列表项的模糊强度（更低，降低滚动成本）。
  static const double listBlurSigma = 8;

  /// 圆角。
  static const double radius = 18;

  /// 浅色主题。
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.light,
    );
    return _base(scheme);
  }

  /// 深色主题。
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 背景交给 GlassScaffold 的渐变处理，这里设为透明避免两层底色打架。
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: inkOf(isDark: isDark, alpha: 0.06),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: inkOf(isDark: isDark, alpha: 0.04),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        isDense: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: inkOf(isDark: isDark, alpha: 0.08),
        space: 1,
      ),
    );
  }

  /// 玻璃层颜色。
  ///
  /// 浅色下用白色半透明、深色下用白色更低的半透明——两边都用白色是刻意的，
  /// 因为在深色背景上叠加白色半透明才是「玻璃」，叠加黑色会变成「塑料」。
  static Color surfaceOf({required bool isDark, double alpha = 0.55}) =>
      Colors.white.withValues(alpha: isDark ? alpha * 0.12 : alpha);

  /// 边框颜色。玻璃需要一层极细的高光边才像玻璃。
  static Color borderOf({required bool isDark, double alpha = 0.28}) =>
      Colors.white.withValues(alpha: isDark ? alpha * 0.5 : alpha);

  /// 前景墨色（用于分隔线、次级背景）。
  static Color inkOf({required bool isDark, double alpha = 0.1}) =>
      (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);

  /// 文字色（保证对比度）。
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.92);

  /// 次级文字色。
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);

  /// 日志级别对应颜色。
  static Color levelColor(String level, {required bool isDark}) {
    switch (level.toUpperCase()) {
      case 'ERROR':
        return isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828);
      case 'WARN':
        return isDark ? const Color(0xFFFFCC80) : const Color(0xFFB26A00);
      case 'INFO':
        return isDark ? const Color(0xFF80D8FF) : const Color(0xFF00695C);
      default:
        return isDark ? const Color(0xFFB0BEC5) : const Color(0xFF546E7A);
    }
  }
}
