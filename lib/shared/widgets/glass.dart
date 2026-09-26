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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? blurSigma;
  final double radius;
  final VoidCallback? onTap;

  /// 左侧强调色（用于区分状态，例如在线绿色、错误红色）。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: blurSigma ?? GlassTheme.blurSigma,
          sigmaY: blurSigma ?? GlassTheme.blurSigma,
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: GlassTheme.surfaceOf(isDark: isDark),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: GlassTheme.borderOf(isDark: isDark)),
          ),
          child: child,
        ),
      ),
    );

    final wrapped = accent == null
        ? content
        : Stack(
            children: [
              content,
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
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
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
    this.blurSigma = GlassTheme.listBlurSigma,
  });

  final LogEntry entry;
  final VoidCallback? onTap;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final levelColor = GlassTheme.levelColor(entry.level.label, isDark: isDark);

    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      radius: 12,
      blurSigma: blurSigma,
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
class GlassButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return GlassPanel(
      radius: 12,
      blurSigma: GlassTheme.listBlurSigma,
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 6 : 9,
      ),
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 14 : 16),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? 12 : 13,
                fontWeight: FontWeight.w600,
                color: GlassTheme.textPrimary(context),
              ),
            ),
          ],
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
    return Center(
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
    );
  }
}
