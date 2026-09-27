import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../data/repository/stats_repository.dart';
import '../../shared/widgets/glass.dart';

/// 统计 Tab（应用的默认首页）。
///
/// 只看两件事：**收到多少消息、发出多少消息**。
/// 之所以把它们放在首页而不是塞进「设置」或「日志」里：
/// 这两个数字是判断「机器人今天到底有没有在干活」最快的方式——
/// 连接状态只说明「连上了」，消息量才说明「真的在收发」。
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  /// 折线图展示的天数。
  static const List<int> _ranges = [7, 14, 30];

  int _range = 7;

  /// 被点选的日期下标（`null` 表示未选中）。
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);

    return ListenableBuilder(
      listenable: services.stats,
      builder: (context, _) {
        final stats = services.stats;
        final points = stats.recentDays(_range);
        final today = stats.dayOf(DateTime.now());

        return GlassScaffold(
          title: '统计',
          body: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 40),
            children: [
              GlassSectionTitle(text: '累计'),
              FadeSlideIn(
                child: GlassPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: _BigNumber(
                          label: '收到消息',
                          value: stats.totalReceived,
                          color: _receivedColor(context),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 42,
                        color: GlassTheme.borderOf(
                          isDark: Theme.of(context).brightness == Brightness.dark,
                        ),
                      ),
                      Expanded(
                        child: _BigNumber(
                          label: '发出消息',
                          value: stats.totalSent,
                          color: _sentColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              GlassSectionTitle(text: '今日'),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: GlassPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SmallNumber(
                          label: '收到',
                          value: today.received,
                          color: _receivedColor(context),
                        ),
                      ),
                      Expanded(
                        child: _SmallNumber(
                          label: '发出',
                          value: today.sent,
                          color: _sentColor(context),
                        ),
                      ),
                      Expanded(
                        child: _SmallNumber(
                          label: '合计',
                          value: today.total,
                          color: GlassTheme.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              GlassSectionTitle(text: '趋势'),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: GlassPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _Legend(
                            color: _receivedColor(context),
                            label: '收到',
                          ),
                          const SizedBox(width: 12),
                          _Legend(color: _sentColor(context), label: '发出'),
                          const Spacer(),
                          for (final range in _ranges)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: GlassChip(
                                label: '$range 天',
                                selected: _range == range,
                                onTap: () => setState(() {
                                  _range = range;
                                  _selected = null;
                                }),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // 选中态读数：点哪一天就显示哪一天的明细。
                      // 没有它的话，折线图只能看出「大概哪天多」，
                      // 具体数字还得靠眼睛去估。
                      _Readout(
                        points: points,
                        selected: _selected,
                        receivedColor: _receivedColor(context),
                        sentColor: _sentColor(context),
                      ),
                      const SizedBox(height: 6),
                      _Chart(
                        points: points,
                        selected: _selected,
                        onSelect: (index) => setState(() => _selected = index),
                        receivedColor: _receivedColor(context),
                        sentColor: _sentColor(context),
                      ),
                      if (stats.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '还没有数据。收到或发出第一条消息后，这里会开始记录'
                            '（统计从本版本起累积，不含此前的历史消息）。',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.6,
                              color: GlassTheme.textSecondary(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              GlassSectionTitle(text: '说明'),
              FadeSlideIn(
                delay: const Duration(milliseconds: 180),
                child: GlassPanel(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    '统计只计**消息**本身，不含入群、推送开关这类事件；'
                    '去重后的重复推送只算一次。\n'
                    '数据保存在本机，按天聚合，最多保留 730 天。',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.7,
                      color: GlassTheme.textSecondary(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 收到的消息用青蓝色。
  static Color _receivedColor(BuildContext context) =>
      GlassTheme.levelColor(
        'INFO',
        isDark: Theme.of(context).brightness == Brightness.dark,
      );

  /// 发出的消息用琥珀色——与连接状态里的「进行中」同色系，
  /// 语义上都是「本机主动做的事」。
  static Color _sentColor(BuildContext context) =>
      GlassTheme.levelColor(
        'WARN',
        isDark: Theme.of(context).brightness == Brightness.dark,
      );
}

/// 大号累计数字。
class _BigNumber extends StatelessWidget {
  const _BigNumber({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: GlassTheme.textSecondary(context),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _compact(value),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: color,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

/// 小号数字（今日）。
class _SmallNumber extends StatelessWidget {
  const _SmallNumber({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _compact(value),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: GlassTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: GlassTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }
}

/// 选中日期的读数。
class _Readout extends StatelessWidget {
  const _Readout({
    required this.points,
    required this.selected,
    required this.receivedColor,
    required this.sentColor,
  });

  final List<DailyStat> points;
  final int? selected;
  final Color receivedColor;
  final Color sentColor;

  @override
  Widget build(BuildContext context) {
    final index = selected;
    if (index == null || index < 0 || index >= points.length) {
      return Text(
        '点击折线可查看某一天的明细',
        style: TextStyle(
          fontSize: 11.5,
          color: GlassTheme.textSecondary(context),
        ),
      );
    }
    final point = points[index];
    return Row(
      children: [
        Text(
          _dateLabel(point.day),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: GlassTheme.textPrimary(context),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '收到 ${point.received}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: receivedColor,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '发出 ${point.sent}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: sentColor,
          ),
        ),
      ],
    );
  }
}

/// 折线图容器：负责把点击位置换算成数据下标。
class _Chart extends StatelessWidget {
  const _Chart({
    required this.points,
    required this.selected,
    required this.onSelect,
    required this.receivedColor,
    required this.sentColor,
  });

  final List<DailyStat> points;
  final int? selected;
  final ValueChanged<int?> onSelect;
  final Color receivedColor;
  final Color sentColor;

  static const double _height = 180;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final index = _indexFor(details.localPosition.dx, width, points.length);
            // 再点一次同一天＝取消选中，省得用户找不到「取消」的入口。
            onSelect(index == selected ? null : index);
          },
          child: SizedBox(
            height: _height,
            width: width,
            child: CustomPaint(
              painter: _LineChartPainter(
                points: points,
                selected: selected,
                receivedColor: receivedColor,
                sentColor: sentColor,
                gridColor: GlassTheme.borderOf(isDark: isDark),
                labelColor: GlassTheme.textSecondary(context),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 把横坐标换算成下标。
  ///
  /// 与画笔里的几何保持一致（同一套 padding 常量），
  /// 否则点上会出现「手指在这里、高亮在那里」的偏差。
  static int? _indexFor(double dx, double width, int count) {
    if (count <= 0) return null;
    final plot = _LineChartPainter.plotRect(Size(width, _height));
    if (plot.width <= 0) return null;
    final step = count == 1 ? 0.0 : plot.width / (count - 1);
    if (step == 0) return 0;
    final index = ((dx - plot.left) / step).round();
    return index.clamp(0, count - 1);
  }
}

/// 折线图绘制。
///
/// 自己画而不是引入图表库的两个理由：
/// 1. 只需要两条折线，图表库带来的体积与 API 面积远大于收益
///    （本项目刻意把依赖控制在最小集）；
/// 2. 视觉要跟玻璃主题一致（网格线用主题边框色、文字用主题次要色），
///    图表库的默认样式反而要写更多代码去覆盖。
class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.points,
    required this.selected,
    required this.receivedColor,
    required this.sentColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<DailyStat> points;
  final int? selected;
  final Color receivedColor;
  final Color sentColor;
  final Color gridColor;
  final Color labelColor;

  /// 绘图区（去掉左侧刻度与底部日期标签）。
  static Rect plotRect(Size size) => Rect.fromLTRB(
        34,
        10,
        size.width - 6,
        size.height - 22,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final plot = plotRect(size);
    if (plot.width <= 0 || plot.height <= 0) return;

    final maxY = _niceMax();
    _paintGrid(canvas, plot, maxY);
    if (points.isEmpty) return;

    final step = points.length == 1 ? 0.0 : plot.width / (points.length - 1);
    Offset pointAt(int index, int value) {
      final x = plot.left + step * index;
      final ratio = maxY == 0 ? 0.0 : value / maxY;
      return Offset(x, plot.bottom - plot.height * ratio);
    }

    // 先画填充再画线：线要压在填充上，否则填充的半透明会盖住线尾。
    _paintSeries(
      canvas,
      plot,
      (i) => pointAt(i, points[i].received).dy,
      receivedColor,
      step,
    );
    _paintSeries(
      canvas,
      plot,
      (i) => pointAt(i, points[i].sent).dy,
      sentColor,
      step,
    );

    // 点位：只有点少的时候画，30 天时 60 个圆点会把线糊成一团。
    if (points.length <= 16) {
      for (var i = 0; i < points.length; i++) {
        canvas.drawCircle(
          pointAt(i, points[i].received),
          2.6,
          Paint()..color = receivedColor,
        );
        canvas.drawCircle(
          pointAt(i, points[i].sent),
          2.6,
          Paint()..color = sentColor,
        );
      }
    }

    _paintXLabels(canvas, plot, step);

    final index = selected;
    if (index != null && index >= 0 && index < points.length) {
      _paintSelection(canvas, plot, index, pointAt);
    }
  }

  /// 系列折线 + 渐变填充。
  void _paintSeries(
    Canvas canvas,
    Rect plot,
    double Function(int) yAt,
    Color color,
    double step,
  ) {
    if (points.isEmpty) return;

    final line = Path();
    final fill = Path();
    for (var i = 0; i < points.length; i++) {
      final x = plot.left + step * i;
      final y = yAt(i);
      if (i == 0) {
        line.moveTo(x, y);
        fill.moveTo(x, plot.bottom);
        fill.lineTo(x, y);
      } else {
        line.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(plot.left + step * (points.length - 1), plot.bottom);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(plot),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintGrid(Canvas canvas, Rect plot, double maxY) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    // 三条线：0、中值、最大值。再多会盖过数据本身。
    for (final ratio in [0.0, 0.5, 1.0]) {
      final y = plot.bottom - plot.height * ratio;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), paint);
      _paintText(
        canvas,
        (maxY * ratio).round().toString(),
        Offset(plot.left - 6, y),
        align: TextAlign.right,
        anchorRight: true,
        centerVertically: true,
      );
    }
  }

  void _paintXLabels(Canvas canvas, Rect plot, double step) {
    if (points.isEmpty) return;
    // 只标首、中、尾：30 天时全标会互相压成一片黑。
    final indices = points.length <= 3
        ? List<int>.generate(points.length, (i) => i)
        : [0, points.length ~/ 2, points.length - 1];
    for (final i in indices.toSet()) {
      final x = plot.left + step * i;
      _paintText(
        canvas,
        _dateLabel(points[i].day),
        Offset(x, plot.bottom + 5),
        centerHorizontally: true,
        clampToWidth: plot,
      );
    }
  }

  void _paintSelection(
    Canvas canvas,
    Rect plot,
    int index,
    Offset Function(int, int) pointAt,
  ) {
    final x = pointAt(index, 0).dx;
    canvas.drawLine(
      Offset(x, plot.top),
      Offset(x, plot.bottom),
      Paint()
        ..color = labelColor.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
    for (final entry in [
      (points[index].received, receivedColor),
      (points[index].sent, sentColor),
    ]) {
      final center = pointAt(index, entry.$1);
      canvas.drawCircle(center, 5.5, Paint()..color = entry.$2.withValues(alpha: 0.25));
      canvas.drawCircle(center, 3.2, Paint()..color = entry.$2);
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset anchor, {
    TextAlign align = TextAlign.left,
    bool anchorRight = false,
    bool centerVertically = false,
    bool centerHorizontally = false,
    Rect? clampToWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: labelColor),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();

    var dx = anchor.dx;
    if (anchorRight) dx -= painter.width;
    if (centerHorizontally) dx -= painter.width / 2;
    var dy = anchor.dy;
    if (centerVertically) dy -= painter.height / 2;
    if (clampToWidth != null) {
      dx = dx.clamp(clampToWidth.left, clampToWidth.right - painter.width);
    }
    painter.paint(canvas, Offset(dx, dy));
  }

  /// 纵轴上限取「整齐的」数字，避免出现 37 这种刻度。
  double _niceMax() {
    var maxValue = 0;
    for (final point in points) {
      maxValue = [maxValue, point.received, point.sent].reduce(
        (a, b) => a > b ? a : b,
      );
    }
    if (maxValue <= 0) return 1;
    final magnitude = maxValue <= 10
        ? 1
        : (maxValue <= 50 ? 10 : (maxValue <= 200 ? 20 : 50));
    // 向上取到 magnitude 的整数倍。
    final rounded = ((maxValue + magnitude - 1) ~/ magnitude) * magnitude;
    return rounded.toDouble();
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      old.points != points ||
      old.selected != selected ||
      old.receivedColor != receivedColor ||
      old.sentColor != sentColor ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor;
}

/// `8/27` 形式的短日期。
String _dateLabel(DateTime day) => '${day.month}/${day.day}';

/// 大数字压缩显示：过万后用「万」，避免一行放不下把布局撑破。
String _compact(int value) {
  if (value < 10000) return '$value';
  final wan = value / 10000;
  return '${wan.toStringAsFixed(wan >= 100 ? 0 : 1)}万';
}
