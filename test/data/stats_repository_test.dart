import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/data/local/json_doc_store.dart';
import 'package:lavedevelop/data/repository/stats_repository.dart';

/// 内存版存储。
///
/// 不碰真实文件：统计的全部逻辑都在内存里，落盘只是搬运，
/// 用文件反而把测试变成对 `path_provider` 的依赖。
class _MemoryStore implements ListStoreLike {
  final Map<String, List<Map<String, dynamic>>> data = {};

  @override
  Future<List<Map<String, dynamic>>> readList(String key) async =>
      data[key] ?? const [];

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {
    // 存副本：真实实现也是序列化后写入，共享引用会让「读回来的数据」
    // 与「内存里的数据」同步变化，掩盖掉持久化本身的问题。
    data[key] = items.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

void main() {
  group('StatsRepository', () {
    test('按天聚合收发计数，并给出累计', () {
      final repo = StatsRepository(store: _MemoryStore());

      repo.recordReceived();
      repo.recordReceived();
      repo.recordSent();

      expect(repo.totalReceived, 2);
      expect(repo.totalSent, 1);
      expect(repo.isEmpty, isFalse);

      final today = repo.dayOf(DateTime.now());
      expect(today.received, 2);
      expect(today.sent, 1);
      expect(today.total, 3);
    });

    test('缺失的日期补零，而不是被跳过', () {
      final now = DateTime(2026, 9, 27, 10);
      final repo = StatsRepository(store: _MemoryStore(), now: () => now);

      repo.recordReceived();

      final days = repo.recentDays(7);
      expect(days, hasLength(7));
      // 折线图的横轴必须连续：某天没有消息要画成 0，
      // 否则「那天完全没动静」这件事在图上就消失了。
      expect(days.first.received, 0);
      expect(days.first.day, DateTime(2026, 9, 21));
      expect(days.last.day, DateTime(2026, 9, 27));
      expect(days.last.received, 1);
    });

    test('跨天分开计数', () {
      var now = DateTime(2026, 9, 26, 23, 59);
      final repo = StatsRepository(store: _MemoryStore(), now: () => now);

      repo.recordReceived();
      repo.recordSent();

      // 跨过午夜。
      now = DateTime(2026, 9, 27, 0, 1);
      repo.recordReceived();

      expect(repo.dayOf(DateTime(2026, 9, 26)).received, 1);
      expect(repo.dayOf(DateTime(2026, 9, 26)).sent, 1);
      expect(repo.dayOf(DateTime(2026, 9, 27)).received, 1);
      expect(repo.dayOf(DateTime(2026, 9, 27)).sent, 0);

      // 累计不随日期变化。
      expect(repo.totalReceived, 2);
      expect(repo.totalSent, 1);
    });

    test('落盘后可被新实例恢复（累计与每日都还原）', () async {
      final store = _MemoryStore();
      final now = DateTime(2026, 9, 27, 12);

      final writer = StatsRepository(store: store, now: () => now);
      writer.recordReceived();
      writer.recordReceived();
      writer.recordSent();
      await writer.flush();

      final reader = StatsRepository(store: store, now: () => now);
      await reader.restore();

      expect(reader.totalReceived, 2);
      expect(reader.totalSent, 1);
      expect(reader.dayOf(DateTime(2026, 9, 27)).total, 3);
    });

    test('清空后累计与每日一起归零', () async {
      final repo = StatsRepository(store: _MemoryStore());
      repo.recordReceived();
      await repo.clear();

      expect(repo.totalReceived, 0);
      expect(repo.totalSent, 0);
      expect(repo.isEmpty, isTrue);
      expect(repo.recentDays(7).every((d) => d.total == 0), isTrue);
    });

    test('超过保留上限时裁掉最老的天，但累计不倒退', () async {
      final store = _MemoryStore();
      var now = DateTime(2026, 1, 1, 12);
      final repo = StatsRepository(store: store, maxDays: 3, now: () => now);

      for (var i = 0; i < 5; i++) {
        repo.recordReceived();
        now = now.add(const Duration(days: 1));
      }

      expect(repo.activeDays, 3, reason: '只保留最近 3 天');
      // 累计是「历史总量」，裁剪老数据不该让它变小。
      expect(repo.totalReceived, 5);
    });

    test('存储损坏时按空数据继续，不抛异常', () async {
      final store = _MemoryStore();
      store.data['stats'] = [
        {'day': '2026-09-27', 'received': 'not-a-number'},
      ];
      final repo = StatsRepository(store: store);

      await repo.restore();

      expect(repo.totalReceived, 0);
      expect(repo.isEmpty, isTrue);
    });
  });
}
