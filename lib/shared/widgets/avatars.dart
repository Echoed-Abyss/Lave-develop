import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// 通用头像。
///
/// ## 为什么要做成「有图用图、没图用确定性占位」
///
/// 官方对**单聊 / 群聊**的消息事件（`C2C_MESSAGE_CREATE`、
/// `GROUP_AT_MESSAGE_CREATE`）的 `author` 对象里**没有 `avatar` 字段**——
/// 那里只有各种 openid 与昵称；官方也没有提供「按 openid 查用户资料」的接口。
/// 换句话说，**用户侧的头像数据在官方 API 里取不到**。
///
/// 因此本组件同时支持两条路径：
///
/// 1. [imageUrl] 有值就加载真实头像。机器人自己的头像确实拿得到
///    （`GET /users/@me` 的 `avatar`），消息事件的 author 一旦也带上该字段
///    就会自动生效，不需要改代码；
/// 2. 没有就渲染确定性占位：颜色由 [seed] 稳定推导，文字取 [label] 首字。
///    同一个对象每次进来颜色都一样，不会出现「同一个人在两处不同色」。
///
/// 刻意不做「按 openid 猜 QQ 头像 URL」这类事：那种 URL 依赖非公开的
/// 映射关系，既不可靠也不合规。
class LaveAvatar extends StatelessWidget {
  const LaveAvatar({
    super.key,
    required this.seed,
    this.imageUrl,
    this.label,
    this.radius = 16,
    this.isBot = false,
    this.accent,
  });

  /// 稳定键，用于占位色与首字的推导（一般传 openid 或 AppID）。
  final String seed;

  /// 真实头像地址；为空或加载失败时退回占位。
  final String? imageUrl;

  /// 展示名（占位取首字）。
  final String? label;

  /// 半径（直径 = 2 × radius）。
  final double radius;

  /// 是否为机器人。机器人无头像时用机器人图标 + 状态色，
  /// 与「用户」在视觉上区分开。
  final bool isBot;

  /// 强调色（机器人卡片用它表达连接状态）。
  final Color? accent;

  /// 占位调色板。
  ///
  /// 选的是中等饱和度的颜色：既能在浅色玻璃背景上可读，
  /// 又不会在深色背景下刺眼。
  static const List<Color> _palette = [
    Color(0xFF4A7DB5),
    Color(0xFF2E9E6B),
    Color(0xFFB5763D),
    Color(0xFF8A5CB8),
    Color(0xFFB5485F),
    Color(0xFF3E8FA8),
    Color(0xFF7A8C3E),
    Color(0xFF9E5F97),
  ];

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;

    final fallback = _fallback(context);

    if (!hasImage) return fallback;

    // 用 clipBehavior 的圆形裁剪套在 Image 外层，而不是用 CircleAvatar 的
    // backgroundImage：后者在任何一次重建里都可能重新触发解码，
    // 而 Image.network 会走图片缓存，列表滚动时明显更省。
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // 按显示尺寸解码。头像来回滚动的场景下，这一步能省掉大量
        // 「解码成 1080×1080 再缩到 32×32」的无用功。
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        // 预签名 URL 过期、断网都会走到这里，直接退回占位而不是留一个空洞。
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final size = radius * 2;
    final color = accent ?? _colorFor(seed);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
      ),
      alignment: Alignment.center,
      child: isBot
          ? Icon(Icons.smart_toy_rounded, size: radius * 0.95, color: color)
          : Text(
              _initial(label, seed),
              style: TextStyle(
                fontSize: radius * 0.86,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1,
              ),
            ),
    );
  }

  /// 取昵称首字；昵称缺失时退回首字可用字符，都没有就用一个中性符号。
  ///
  /// 用 `runes.first` 而不是 `substring(0, 1)`：后者会把 emoji 之类
  /// 非 BMP 字符劈成半个代理对，渲染出乱码方块。代价是 ZWJ 组合 emoji
  /// 仍会被截断，但那只影响观感，不会出乱码。
  static String _initial(String? label, String seed) {
    for (final source in [label, seed]) {
      final text = source?.trim();
      if (text == null || text.isEmpty) continue;
      final first = String.fromCharCode(text.runes.first);
      if (first.trim().isNotEmpty) return first;
    }
    return '?';
  }

  /// 由 [seed] 稳定推导一个颜色。
  ///
  /// 不用 `String.hashCode`：Dart 不保证它在不同进程/版本间一致，
  /// 那会导致「同一个人昨天是蓝色今天是绿色」。这里自己算一个简单稳定的和。
  static Color _colorFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }
}

/// 带在线状态描边的机器人头像。
///
/// 与 [LaveAvatar] 分开是因为这里多一层「状态环」——
/// 机器人卡片上头像本身就是状态的载体，而消息气泡里不需要。
class BotStatusAvatar extends StatelessWidget {
  const BotStatusAvatar({
    super.key,
    required this.seed,
    required this.accent,
    this.imageUrl,
    this.label,
    this.radius = 15,
  });

  final String seed;
  final Color accent;
  final String? imageUrl;
  final String? label;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(1.6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.75), width: 1.4),
        color: GlassTheme.surfaceOf(isDark: isDark, alpha: 0.35),
      ),
      child: LaveAvatar(
        seed: seed,
        imageUrl: imageUrl,
        label: label,
        radius: radius,
        isBot: true,
        accent: accent,
      ),
    );
  }
}
