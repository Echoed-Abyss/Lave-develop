import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/log_entry.dart';

/// 玻璃视觉组件集。
///
/// 全部组件封装在这里而不是散落在各页面，原因有两个：
/// 1. `BackdropFilter` 的成本与用法容易写错（漏掉 `ClipRRect` 会导致
///    整个页面重绘），集中一处便于统一控制；
/// 2. 主题切换时只需改这里，各页面不用跟着动。

/// 玻璃页面骨架：负责背景渐变与安全区。
///
/// 玻璃效果依赖背景有内容，因此背景必须是渐变而不是纯色——
/// 否则「半透明 + 模糊」看起来就是一块灰。
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: isDark
            ? GlassTheme.darkBackground
            : GlassTheme.lightBackground,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: title == null
            ? null
            : AppBar(
                title: Text(title!),
                actions: actions,
              ),
        body: body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

/// 玻璃面板。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.blurSigma,
    this.radius = GlassTheme.radius,
    this.onTap,
    this.accent,
    this.blur = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? blurSigma;
  final double radius;
  final VoidCallback? onTap;

  /// 左侧强调色（用于区分状态，例如在线绿色、错误红色）。
  final Color? accent;

  /// 是否对背景做模糊。
  ///
  /// **长列表里的条目应当传 `false`**：`BackdropFilter` 是 GPU 上最贵的
  /// 常规操作之一，滚动时每个可见条目各做一次，在中低端机上会直接掉帧。
  /// 关掉后仍保留半透明底色与描边，视觉上依然是「玻璃」，只是不再折射背景。
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final decoration = BoxDecoration(
      // 关闭模糊时把底色做厚一点，否则缺少折射会让面板「发飘」。
      color: GlassTheme.surfaceOf(isDark: isDark, alpha: blur ? 0.55 : 0.88),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: GlassTheme.borderOf(isDark: isDark)),
    );

    final surface = blur
        ? RepaintBoundary(
            // RepaintBoundary 让模糊结果被缓存成独立图层：
            // 父级重绘（例如滚动、动画）时不必重新做一遍模糊。
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blurSigma ?? GlassTheme.blurSigma,
                  sigmaY: blurSigma ?? GlassTheme.blurSigma,
                ),
                child: Container(
                  padding: padding,
                  decoration: decoration,
                  child: child,
                ),
              ),
            ),
          )
        : Container(padding: padding, decoration: decoration, child: child);

    final wrapped = accent == null
        ? surface
        : Stack(
            children: [
              surface,
              Positioned(
                left: 0,
                top: 14,
                bottom: 14,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          );

    final tappable = onTap == null
        ? wrapped
        : InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: wrapped,
          );

    return margin == null
        ? tappable
        : Padding(padding: margin!, child: tappable);
  }
}

/// 可折叠的玻璃卡片。
///
/// 需求点名要的组件。折叠状态用内部 `StatefulWidget` 维护而不是外部传入：
/// 卡片数量多时（例如 20 个机器人），把展开状态提到全局会让
/// 任何一次展开都触发整棵树重建。
class GlassExpandableCard extends StatefulWidget {
  const GlassExpandableCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.accent,
    this.children = const [],
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Color? accent;

  /// 展开后显示的内容。
  final List<Widget> children;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<GlassExpandableCard> createState() => _GlassExpandableCardState();
}

class _GlassExpandableCardState extends State<GlassExpandableCard>
    with SingleTickerProviderStateMixin {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      accent: widget.accent,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() => _expanded = !_expanded);
              widget.onExpansionChanged?.call(_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                            color: GlassTheme.textPrimary(context),
                          ),
                        ),
                        if (widget.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(
                              widget.subtitle!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: GlassTheme.textSecondary(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.trailing != null) widget.trailing!,
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: GlassTheme.textSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          // 用 AnimatedSize + 条件子树，而不是 AnimatedCrossFade。
          //
          // AnimatedCrossFade 会**同时保留并构建两个子树**（收起的那个也在建），
          // 卡片内容重时等于白算一遍布局与绘制；AnimatedSize 只构建当前子树，
          // 仅在高度变化时做尺寸动画。
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: widget.children,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ),
        ],
      ),
    );
  }
}

/// 玻璃日志条目：时间戳 + 等级 + 内容。
///
/// 需求点名的组件。布局要点：时间与等级用等宽字体固定宽度，
/// 这样多条日志纵向排列时正文能对齐，扫读效率差别很大。
class GlassLogItem extends StatelessWidget {
  const GlassLogItem({
    super.key,
    required this.entry,
    this.onTap,
  });

  final LogEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final levelColor = GlassTheme.levelColor(entry.level.label, isDark: isDark);

    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      radius: 12,
      // 日志列表可能同时挂上千条记录（ListView 虽懒构建，
      // 可见条目也有十来个），逐条做背景模糊会让滚动明显掉帧。
      blur: false,
      onTap: onTap,
      accent: entry.isHighlighted ? levelColor : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间戳：固定宽度，保证多行对齐。
          SizedBox(
            width: 62,
            child: Text(
              LogEntry.formatTime(entry.at),
              style: TextStyle(
                fontSize: 11.5,
                fontFamily: 'monospace',
                fontFeatures: const [FontFeature.tabularFigures()],
                color: GlassTheme.textSecondary(context),
              ),
            ),
          ),
          // 等级：固定宽度色块文字。
          SizedBox(
            width: 44,
            child: Text(
              entry.level.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: levelColor,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: TextStyle(
                    fontSize: 13,
                    color: GlassTheme.textPrimary(context),
                  ),
                ),
                if (entry.detail != null && entry.detail!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      entry.detail!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: GlassTheme.textSecondary(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            entry.source.label,
            style: TextStyle(
              fontSize: 11,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 玻璃按钮。
///
/// 按下时做轻微缩放反馈。用 [AnimatedScale] 而不是自定义动画控制器：
/// 隐式动画只在值变化时驱动一帧，不占用常驻 ticker，对列表里的多个按钮更划算。
class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool dense;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: GlassPanel(
          radius: 12,
          blur: false,
          padding: EdgeInsets.symmetric(
            horizontal: widget.dense ? 10 : 14,
            vertical: widget.dense ? 6 : 9,
          ),
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: widget.dense ? 14 : 16),
                  const SizedBox(width: 5),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: widget.dense ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: GlassTheme.textPrimary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃筛选标签。
class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? (color ?? GlassTheme.brand).withValues(alpha: isDark ? 0.3 : 0.2)
                : GlassTheme.surfaceOf(isDark: isDark, alpha: 0.35),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? (color ?? GlassTheme.brand).withValues(alpha: 0.6)
                  : GlassTheme.borderOf(isDark: isDark),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? (color ?? GlassTheme.brand)
                  : GlassTheme.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// 玻璃输入框。
class GlassTextField extends StatelessWidget {
  const GlassTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscure = false,
    this.maxLines = 1,
    this.suffix,
    this.helper,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscure;
  final int maxLines;
  final Widget? suffix;
  final String? helper;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        maxLines: obscure ? 1 : maxLines,
        enabled: enabled,
        // 凭证类输入关闭自动纠错与联想：避免密钥被输入法改写或上传。
        autocorrect: !obscure,
        enableSuggestions: !obscure,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helper,
          suffixIcon: suffix,
          filled: true,
        ),
      ),
    );
  }
}

/// 区块标题。
class GlassSectionTitle extends StatelessWidget {
  const GlassSectionTitle({super.key, required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: GlassTheme.textSecondary(context),
              ),
            ),
          ),
          // 使用 null-aware 元素：`?trailing` 等价于「非空才加入」。
          ?trailing,
        ],
      ),
    );
  }
}

/// 空状态提示。
class GlassEmptyState extends StatelessWidget {
  const GlassEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassPanel(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 34, color: GlassTheme.textSecondary(context)),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: GlassTheme.textPrimary(context),
                  ),
                ),
                if (description != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      description!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.6,
                        color: GlassTheme.textSecondary(context),
                      ),
                    ),
                  ),
                if (action != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: action!,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 一次性入场动效：淡入 + 轻微上移。
///
/// 刻意用隐式动画而不是 `AnimationController`：
/// 动画只跑一次就停在终态，不留下常驻的 ticker；
/// 列表里放几十个这样的组件也不会持续占用帧回调。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 0.08,
  });

  final Widget child;

  /// 延迟。用于做错落感，**不要给长列表逐条加延迟**：
  /// 条目一多就会显得整页在「慢慢加载」，反而不利索。
  final Duration delay;

  /// 起始纵向偏移（相对自身高度的比例）。
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      // 必须等到首帧之后再切目标值：在 initState 里直接置为 true 的话，
      // 隐式动画的起始值与目标值相同，动画根本不会发生。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _visible = true);
      });
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : Offset(0, widget.offset),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// 状态脉冲点。
///
/// 连接中 / 重连退避时呼吸闪烁，在线时静止 —— 让「正在努力但还没连上」
/// 与「已经好了」在视觉上区分开，避免用户看到静止的灰点以为程序卡死。
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 8,
    this.animate = false,
  });

  final Color color;
  final double size;

  /// 是否呼吸。仅在「进行中」状态传 true。
  final bool animate;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  // 必须在 initState 里显式创建，**不能用 `late final` 惰性初始化**。
  //
  // 惰性字段只在第一次被读取时才求值：当 animate 为 false 时它从未被读过，
  // 于是 dispose() 里的 `_controller.dispose()` 成了首次求值 ——
  // 那一刻元素已经处于 deactivated 状态，AnimationController 创建 Ticker 时
  // 查找 TickerMode ancestor 会直接抛
  // 「Looking up a deactivated widget's ancestor is unsafe」。
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.animate) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在状态切换时启停动画。让它一直跑着会白白占一个每帧回调。
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.animate
          ? Tween<double>(begin: 0.35, end: 1).animate(_controller)
          : const AlwaysStoppedAnimation<double>(1),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: 0.5),
              blurRadius: widget.size,
              spreadRadius: widget.size / 6,
            ),
          ],
        ),
      ),
    );
  }
}
