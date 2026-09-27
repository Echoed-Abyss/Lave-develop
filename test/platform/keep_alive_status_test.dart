import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/platform/android_keep_alive.dart';

KeepAliveStatus _status({
  bool running = true,
  String foregroundType = 'specialUse',
  bool ignoringBatteryOptimizations = true,
  bool canScheduleExactAlarms = true,
  bool notificationPermission = true,
  int standbyBucket = 10,
  int sdkInt = 36,
}) =>
    KeepAliveStatus(
      running: running,
      foregroundType: foregroundType,
      ignoringBatteryOptimizations: ignoringBatteryOptimizations,
      canScheduleExactAlarms: canScheduleExactAlarms,
      notificationPermission: notificationPermission,
      standbyBucket: standbyBucket,
      sdkInt: sdkInt,
    );

void main() {
  group('保活诊断快照', () {
    test('占位值不会被当成真实结论展示', () {
      // `sdkInt` 为 0 是「根本没查到」的哨兵值，界面据此显示「正在查询」
      // 而不是把一屏 false 当成诊断结果——那会误导用户去改不该改的设置。
      expect(KeepAliveStatus.unavailable.available, isFalse);
      expect(KeepAliveStatus.unavailable.standbyBucketLabel, '未知');
    });

    test('dataSync 被识别为有运行时长上限的类型', () {
      // Android 15 起 dataSync 每 24 小时累计只能跑 6 小时，到点被系统停服。
      // API 34+ 本应走 specialUse，落到 dataSync 就是要报警的异常状态。
      expect(_status(foregroundType: 'dataSync').isLimitedForegroundType, isTrue);
    });

    test('specialUse 与未知类型都不按「有时长上限」处理', () {
      expect(
        _status(foregroundType: 'specialUse').isLimitedForegroundType,
        isFalse,
      );
      // 未知时不能谎报为受限：那会让用户收到一条自己也验证不了的警告。
      expect(
        _status(foregroundType: 'unknown').isLimitedForegroundType,
        isFalse,
      );
    });

    test('待机分桶：RARE 起视为会限制网络', () {
      expect(_status(standbyBucket: 10).standbyBucketRestrictsNetwork, isFalse);
      expect(_status(standbyBucket: 30).standbyBucketRestrictsNetwork, isFalse);
      // 40 = RARE，官方明确「系统还会限制该应用的互联网连接功能」。
      expect(_status(standbyBucket: 40).standbyBucketRestrictsNetwork, isTrue);
      expect(_status(standbyBucket: 50).standbyBucketRestrictsNetwork, isTrue);
      // -1 = 查询失败，不能当成受限。
      expect(_status(standbyBucket: -1).standbyBucketRestrictsNetwork, isFalse);
    });

    test('待机分桶中文名与官方分档一致', () {
      expect(_status(standbyBucket: 10).standbyBucketLabel, '活跃');
      expect(_status(standbyBucket: 20).standbyBucketLabel, '工作集');
      expect(_status(standbyBucket: 30).standbyBucketLabel, '常用');
      expect(_status(standbyBucket: 40).standbyBucketLabel, '极少使用');
      expect(_status(standbyBucket: 50).standbyBucketLabel, '受限');
      expect(_status(standbyBucket: 99).standbyBucketLabel, '未知');
    });
  });
}
