import 'dart:async';

import 'package:flutter/foundation.dart';

import '../local/json_doc_store.dart';

/// 单日收发计数。
@immutable
class DailyCounters {
  const DailyCounters({this.received = 0, this.sent = 0});

  final int received;
  final int sent;

  int get total => received + sent;
}

/// 图表用的一个数据点。
@immutable
class DailyStat {
  const DailyStat({
    required this.day,
    required this.received,
    required this.sent,
  });

  /// 当天零点（本地时区）。
  final DateTime day;

  final int received;
  final int sent;

  int get total => received + sent;
}

/// 消息收发统计。
///
/// ## 为什么自己计数而不是从历史记录里算
///
/// 历史仓库按会话分片、且只保留每个会话最近 500 条，
/// 「总收发量」这种跨全部会话、全时间段的数字从那里算既不准也慢
/// （每渲染一帧都要遍历几万条）。这里维护的是**按天聚合的计数器**：
/// 每次收发只做一次 `+1`，读的时候直接拿现成的数组。
///
/// ## 计数口径
///
/// 只统计「消息」本身，不统计生命周期事件（入群、推送开关等）：
/// 后者在官方口径里是事件而非消息，混进去会让「收消息数」虚高，
/// 而用户看这个数字是想知道「这个机器人一天到底处理了多少条消息」。
class StatsRepository extends ChangeNotifier {
  StatsRepository({
    required ListStoreLike store,
    this.maxDays = 730,
    DateTime Function()? now,
  })  : _store = store,
        _now = now ?? DateTime.now;

  /// 保留的天数上限。
  ///
  /// 取 730（两年）：一条记录只有几十字节，两年也就几十 KB，
  /// 远小于「按天裁剪后总要额外维护一份累计总数」的复杂度。
  final int maxDays;

  final ListStoreLike _store;

  /// 当前时间来源。
  ///
  /// 做成可注入而不是直接调 `DateTime.now()`：跨天归零是本类唯一的
  /// 日期逻辑，若不能替换时间源就无法写确定性测试——
  /// 而「跨天算错了」这种缺陷在真机上要等一整天才会暴露。
  final DateTime Function() _now;

  /// key = `yyyy-MM-dd`（本地日期），value = 当天计数。
  final Map<String, DailyCounters> _days = {};

  int _totalReceived = 0;
  int _totalSent = 0;

  /// 累计收到消息数（自本功能上线起）。
  int get totalReceived => _totalReceived;

  /// 累计发出消息数。
  int get totalSent => _totalSent;

  /// 有数据的天数。
  int get activeDays => _days.length;

  /// 是否还没有任何数据。
  bool get isEmpty => _days.isEmpty;

  /// 最近 [count] 天的数据（含今天），**缺失的日期补零**。
  ///
  /// 必须补零：折线图最怕「只画有数据的天」——那样横轴会被压缩，
  /// 「某天完全没有消息」这个事实就看不见了，而它恰恰是最该被注意到的。
  List<DailyStat> recentDays(int count) {
    final today = _dayKeyOf(_now());
    final result = <DailyStat>[];
    for (var offset = count - 1; offset >= 0; offset--) {
      final day = DateTime(today.year, today.month, today.day - offset);
      final counters = _days[_format(day)];
      result.add(
        DailyStat(
          day: day,
          received: counters?.received ?? 0,
          sent: counters?.sent ?? 0,
        ),
      );
    }
    return result;
  }

  /// 某一天的数据（缺失返回零）。
  DailyStat dayOf(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    final counters = _days[_format(normalized)];
    return DailyStat(
      day: normalized,
      received: counters?.received ?? 0,
      sent: counters?.sent ?? 0,
    );
  }

  /// 记一次收到的消息。
  void recordReceived() => _bump(received: 1);

  /// 记一次发出的消息。
  void recordSent() => _bump(sent: 1);

  void _bump({int received = 0, int sent = 0}) {
    final key = _format(_dayKeyOf(_now()));
    final current = _days[key] ?? const DailyCounters();
    _days[key] = DailyCounters(
      received: current.received + received,
      sent: current.sent + sent,
    );
    _totalReceived += received;
    _totalSent += sent;
    _trimIfNeeded();
    notifyListeners();
    _schedulePersist();
  }

  /// 清空统计（设置页的「重置统计」用）。
  Future<void> clear() async {
    _days.clear();
    _totalReceived = 0;
    _totalSent = 0;
    notifyListeners();
    await _persistNow();
  }

  /// 立即落盘，不等防抖窗口。
  ///
  /// 用途：应用退出前把最近的计数写下去，以及测试里断言持久化结果——
  /// 正常路径走的是 3 秒防抖，测试没法等，也不该等。
  Future<void> flush() async {
    _persistTimer?.cancel();
    await _persistNow();
  }

  /// 从本地载入。
  Future<void> restore() async {
    try {
      for (final item in await _store.readList(_storageKey)) {
        final day = item['day'] as String?;
        if (day == null) continue;
        final received = (item['received'] as num?)?.toInt() ?? 0;
        final sent = (item['sent'] as num?)?.toInt() ?? 0;
        _days[day] = DailyCounters(received: received, sent: sent);
      }
    } catch (_) {
      // 统计损坏不值得让应用打不开：按空数据继续，后续会重新累积。
    }
    _recomputeTotals();
    notifyListeners();
  }

  void _recomputeTotals() {
    _totalReceived = 0;
    _totalSent = 0;
    for (final counters in _days.values) {
      _totalReceived += counters.received;
      _totalSent += counters.sent;
    }
  }

  void _trimIfNeeded() {
    if (_days.length <= maxDays) return;
    final keys = _days.keys.toList()..sort();
    for (final key in keys.take(_days.length - maxDays)) {
      _days.remove(key);
    }
    // 裁剪只删最老的天，累计数保持不变（累计是「历史总量」，不该倒退）。
  }

  static const String _storageKey = 'stats';

  Timer? _persistTimer;

  /// 合并写入：消息密集时每条都落盘会造成 IO 抖动。
  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_persistNow());
    });
  }

  Future<void> _persistNow() async {
    try {
      final payload = <Map<String, dynamic>>[];
      final keys = _days.keys.toList()..sort();
      for (final key in keys) {
        final counters = _days[key]!;
        payload.add({
          'day': key,
          'received': counters.received,
          'sent': counters.sent,
        });
      }
      await _store.writeList(_storageKey, payload);
    } catch (_) {
      // 落盘失败不影响内存中的统计。
    }
  }

  /// 取出日期部分（本地时区）。
  static DateTime _dayKeyOf(DateTime at) =>
      DateTime(at.year, at.month, at.day);

  /// `yyyy-MM-dd`。手写而不是用 intl：只为了一个不依赖语言环境的键。
  static String _format(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date';
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }
}
