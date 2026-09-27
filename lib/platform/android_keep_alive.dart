import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

/// 保活诊断快照。
///
/// 存在的理由：这个功能有太多「开关是开的、服务却没生效」的失败模式
/// （通知权限被拒、后台启动被系统拒绝、Doze 暂停网络、待机分桶限制网络、
/// 前台服务被类型配额掐掉）。只看开关状态根本无法区分它们，
/// 用户能说的只有「机器人不在线」。把原始事实全部摊开，
/// 才能把「猜」变成「看」。
@immutable
class KeepAliveStatus {
  const KeepAliveStatus({
    required this.running,
    required this.foregroundType,
    required this.ignoringBatteryOptimizations,
    required this.canScheduleExactAlarms,
    required this.notificationPermission,
    required this.standbyBucket,
    required this.sdkInt,
  });

  /// 平台不支持（非 Android）或查询失败时的占位值。
  ///
  /// 刻意把 [sdkInt] 记成 0：调用方据此就能区分「真的查到了」与「根本没查」，
  /// 不会把占位值当成真实诊断结论展示给用户。
  static const KeepAliveStatus unavailable = KeepAliveStatus(
    running: false,
    foregroundType: 'unknown',
    ignoringBatteryOptimizations: false,
    canScheduleExactAlarms: false,
    notificationPermission: false,
    standbyBucket: -1,
    sdkInt: 0,
  );

  /// 前台服务是否**真的**在跑（不是「用户开了开关」）。
  final bool running;

  /// 实际生效的前台服务类型：`specialUse` / `dataSync` / `unknown`。
  final String foregroundType;

  /// 是否已在电池优化白名单里（Doze 会暂停非白名单应用的网络访问）。
  final bool ignoringBatteryOptimizations;

  /// 是否已获得精确闹钟权限（决定被清掉后能否自动回来）。
  final bool canScheduleExactAlarms;

  /// 是否已授予通知权限（不影响服务，只影响通知是否可见）。
  final bool notificationPermission;

  /// 应用待机分桶：10 活跃 / 20 工作集 / 30 常用 / 40 极少使用 / 50 受限。
  final int standbyBucket;

  /// 系统 API 级别（0 表示未查询到）。
  final int sdkInt;

  /// 诊断是否真的可用。
  bool get available => sdkInt > 0;

  /// 前台服务类型是否落到了有运行时长上限的 `dataSync`。
  ///
  /// Android 15 起 `dataSync` 每 24 小时累计只能跑 6 小时，
  /// 到点被系统停服。API 34+ 本应走 `specialUse`，出现这个值说明
  /// `specialUse` 启动被 ROM 拒绝了，属于需要修复的异常状态。
  bool get isLimitedForegroundType => foregroundType == 'dataSync';

  /// 待机分桶是否已经开始限制网络访问。
  ///
  /// RARE（40）起系统会限制应用的互联网连接——这是「放着一会儿就掉线」
  /// 的常见原因，且与前台服务是否在跑无关。
  bool get standbyBucketRestrictsNetwork => standbyBucket >= 40;

  /// 待机分桶的中文名。
  String get standbyBucketLabel => switch (standbyBucket) {
        10 => '活跃',
        20 => '工作集',
        30 => '常用',
        40 => '极少使用',
        50 => '受限',
        _ => '未知',
      };
}

/// Android 侧「网关保活前台服务」的桥。
///
/// 存在的理由：Dart 跑在同一个 Linux 进程里，**无法自行改变进程优先级**。
/// 应用退到后台后进程进入 cached 状态，Android 的 cached apps freezer 会在
/// 约 10 秒后把它冻结；一旦冻结，Dart 的定时器不再触发，心跳停发，
/// 网关随即关闭连接（日志里表现为存活几十秒到两分钟就出现关闭码 1002）。
/// 唯一解药是由原生侧起一个真正的前台服务。
///
/// 这个类只负责调用；**何时该保活、通知文案写什么**由
/// `KeepAliveCoordinator` 决定。
///
/// 非 Android 平台（或通道不存在）时所有方法都安全地降级为「不支持」，
/// 不会抛异常——桌面/iOS 上没有前台服务这个概念，插件与连接逻辑不应因此受损。
class AndroidKeepAlive {
  AndroidKeepAlive({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('lave/native');

  final MethodChannel _channel;

  /// 该平台是否支持保活。
  ///
  /// 第一次调用某个方法后才有结论；在此之前按「支持」处理，
  /// 让调用路径保持单一（失败会被 [MissingPluginException] 分支吞掉）。
  bool get isSupported => _supported;
  bool _supported = true;

  /// 启动保活（或重设通知文案）。
  Future<bool> start(String text) => _invoke('keepAliveStart', {'text': text});

  /// 只更新通知文案。
  Future<bool> update(String text) => _invoke('keepAliveUpdate', {'text': text});

  /// 停止保活并把常驻通知撤掉。
  Future<bool> stop() => _invoke('keepAliveStop');

  /// 服务当前是否以前台服务形态运行。
  ///
  /// 与「用户是否开启保活」是两件事：通知权限被拒、后台启动被系统拒绝
  /// 都会让开关是开的而服务没起来，需要靠它区分。
  Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('keepAliveIsRunning') ?? false;
    } on MissingPluginException {
      _supported = false;
      return false;
    } catch (error) {
      AppLogger.warn('查询保活服务状态失败：$error', tag: 'keepalive');
      return false;
    }
  }

  /// 申请通知权限（Android 13+）。
  ///
  /// 返回是否**已经**持有权限。授权框是异步的，返回值不代表用户的选择结果；
  /// 未授权也不影响保活本身，只是常驻通知不显示。
  Future<bool> requestNotificationPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestNotificationPermission') ??
          true;
    } on MissingPluginException {
      _supported = false;
      return true;
    } catch (error) {
      AppLogger.warn('申请通知权限失败：$error', tag: 'keepalive');
      return true;
    }
  }

  /// 应用是否已被加入电池优化白名单。
  ///
  /// 低电耗模式（Doze）会忽略唤醒锁并暂停网络，是否加白直接决定
  /// 「息屏很久之后机器人还在不在线」。
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel
              .invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
    } on MissingPluginException {
      _supported = false;
      return true;
    } catch (error) {
      AppLogger.warn('查询电池优化白名单失败：$error', tag: 'keepalive');
      return true;
    }
  }

  /// 打开系统的电池优化设置页，由用户手动加白。
  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod<bool>('openBatteryOptimizationSettings');
    } on MissingPluginException {
      _supported = false;
    } catch (error) {
      AppLogger.warn('打开电池优化设置失败：$error', tag: 'keepalive');
    }
  }

  /// 直接弹系统的「允许应用在后台运行」对话框。
  ///
  /// 与 [openBatteryOptimizationSettings] 的差别很关键：后者只是打开列表页，
  /// 用户要在几十个应用里自己找到本应用再手动改成「不优化」，
  /// 实际上绝大多数人不会做完。这个动作直接弹一个「允许 / 不允许」的框。
  ///
  /// 返回**请求前**是否已在白名单中（弹窗是异步的，返回值不代表用户的选择）；
  /// 用户选择后再调一次 [isIgnoringBatteryOptimizations] 即可确认。
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } on MissingPluginException {
      _supported = false;
      return false;
    } catch (error) {
      AppLogger.warn('申请忽略电池优化失败：$error', tag: 'keepalive');
      return false;
    }
  }

  /// 一次性取回全部保活诊断事实。
  ///
  /// 任何一项查询失败都退化为 [KeepAliveStatus.unavailable]，
  /// 而不是抛异常：诊断是**辅助**手段，它自己的失败不该影响保活本身，
  /// 更不该让设置页崩掉。
  Future<KeepAliveStatus> status() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('keepAliveStatus');
      if (raw == null) return KeepAliveStatus.unavailable;
      return KeepAliveStatus(
        running: raw['running'] == true,
        foregroundType: raw['foregroundType']?.toString() ?? 'unknown',
        ignoringBatteryOptimizations:
            raw['ignoringBatteryOptimizations'] == true,
        canScheduleExactAlarms: raw['canScheduleExactAlarms'] == true,
        notificationPermission: raw['notificationPermission'] == true,
        standbyBucket: _intOf(raw['standbyBucket']) ?? -1,
        sdkInt: _intOf(raw['sdkInt']) ?? 0,
      );
    } on MissingPluginException {
      _supported = false;
      return KeepAliveStatus.unavailable;
    } catch (error) {
      AppLogger.warn('查询保活诊断失败：$error', tag: 'keepalive');
      return KeepAliveStatus.unavailable;
    }
  }

  /// 平台通道可能把整数送成 `num` 或字符串，两种都要接受。
  static int? _intOf(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 是否已获得精确闹钟权限。
  ///
  /// 这是保活链路里唯一「凭定时到点就能在后台启动前台服务」的手段
  /// （官方后台启动豁免清单中的一条），用于划掉任务后的拉起
  /// 与 15 分钟一次的看门狗巡检。
  ///
  /// Android 14 起该权限默认被拒绝，必须由用户手动开启；
  /// 未开启时退化为不精确闹钟——仍会响，但系统会按省电策略推迟，
  /// 所以「后台能不能自动恢复」的差别很大。
  Future<bool> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? true;
    } on MissingPluginException {
      _supported = false;
      return true;
    } catch (error) {
      AppLogger.warn('查询精确闹钟权限失败：$error', tag: 'keepalive');
      return true;
    }
  }

  /// 打开系统的「闹钟和提醒」授权页，让用户为本应用开启精确闹钟。
  Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod<bool>('openExactAlarmSettings');
    } on MissingPluginException {
      _supported = false;
    } catch (error) {
      AppLogger.warn('打开精确闹钟设置失败：$error', tag: 'keepalive');
    }
  }

  Future<bool> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } on MissingPluginException {
      // 非 Android 平台属正常情况，只记一次即可。
      if (_supported) {
        _supported = false;
        AppLogger.info('当前平台不支持前台服务保活', tag: 'keepalive');
      }
      return false;
    } catch (error) {
      AppLogger.warn('调用保活服务失败（$method）：$error', tag: 'keepalive');
      return false;
    }
  }
}
