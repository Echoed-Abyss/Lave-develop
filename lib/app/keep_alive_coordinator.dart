import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/logging/log_service.dart';
import '../data/local/json_doc_store.dart';
import '../data/repository/bot_repository.dart';
import '../domain/models/log_entry.dart';
import '../gateway/connection_registry.dart';
import '../platform/android_keep_alive.dart';

/// 网关保活协调器。
///
/// 它把「用户意图」与「系统能力」翻译成一个前台服务的起停：
///
/// - **该不该保活** = 用户开关打开 **且** 至少有一个启用的机器人；
///   没有启用任何机器人时保留一个常驻通知只会打扰用户；
/// - **为什么必须是原生前台服务**：见 [AndroidKeepAlive] 的类注释——
///   进程被 cached apps freezer 冻结后心跳停发，连接必断。
///
/// 另外它还是「保活真实状态」的唯一查询口：前台服务可能因为通知权限缺失
/// 或后台启动被系统拒绝而没有真正生效，界面需要能把这层差异显示出来。
class KeepAliveCoordinator extends ChangeNotifier {
  KeepAliveCoordinator({
    required LogService log,
    required BotRepository bots,
    required ConnectionRegistry registry,
    required JsonDocStore store,
    AndroidKeepAlive? bridge,
  })  : _log = log,
        _bots = bots,
        _registry = registry,
        _store = store,
        _bridge = bridge ?? AndroidKeepAlive();

  /// 开关在本地存储里的键名。
  static const String storeKey = 'keep_alive_enabled';

  final LogService _log;
  final BotRepository _bots;
  final ConnectionRegistry _registry;
  final JsonDocStore _store;
  final AndroidKeepAlive _bridge;

  bool _enabled = true;

  /// 已脱离（应用退出收尾）。
  ///
  /// 置位后所有状态变更都不再驱动服务：收尾过程中连接状态还会抖动，
  /// 若不拦住，会把刚撤掉的常驻通知又挂回去。
  bool _detached = false;

  /// 用户是否开启了后台保活。
  bool get isEnabled => _enabled;

  /// 当前平台是否支持（非 Android 为 false）。
  bool get isSupported => _bridge.isSupported;

  /// 上一次真正下发到原生侧的文案；`null` 表示「已停止」。
  ///
  /// 存在的必要性：连接状态每次变化都会触发 `notifyListeners()`，
  /// 而其中包含**每收到一帧就更新 `seq`** 这类高频变更。
  /// 不做去重的话，每来一条消息都会跨一次平台通道去重设通知，
  /// 既浪费又把日志刷满。只有文案或开关真的变了才下发。
  String? _lastApplied;

  /// 从存储恢复开关，并开始跟随连接状态。在应用初始化时调用一次。
  Future<void> start() async {
    final doc = await _store.read();
    final saved = doc[storeKey];
    if (saved is bool) _enabled = saved;

    _bots.addListener(_onChanged);
    _registry.addListener(_onChanged);

    await _sync(trigger: '启动');
  }

  /// 修改开关并持久化。
  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;

    final doc = await _store.read();
    doc[storeKey] = value;
    await _store.write(doc);

    if (value) {
      // 开启时顺手要一次通知权限：没有它前台服务照样成立，
      // 但用户看不到任何提示，会以为「开了没反应」。
      await _bridge.requestNotificationPermission();
    }
    _notify();
    await _sync(trigger: '用户切换');
  }

  /// 应用回到前台时重新确认一次服务状态。
  ///
  /// 必须做这件事的原因：Android 12 起禁止从后台启动前台服务，
  /// 若服务曾被系统回收并因该限制而未能重新进入前台，
  /// 只有等应用回到前台才有机会补上——而 Dart 侧是知道这一时机的唯一一方。
  ///
  /// 这里**强制下发**（`force`）：服务可能已经静默死掉，而本地记录
  /// [\_lastApplied] 仍认为它开着，只做文案比对会把这次补救也吞掉。
  Future<void> reassert() => _sync(trigger: '回到前台', force: true);

  /// 应用是否已被加入电池优化白名单（Doze 会忽略唤醒锁并暂停网络）。
  Future<bool> isIgnoringBatteryOptimizations() =>
      _bridge.isIgnoringBatteryOptimizations();

  /// 前台服务当前是否**真的**在运行。
  ///
  /// 与 [isEnabled] 是两件事：开关表达用户意图，这个表达系统事实。
  /// 通知权限被拒、系统拒绝从后台启动前台服务时，两者会不一致，
  /// 界面必须能把这种差异显示出来，否则用户只会看到「开关是开的、
  /// 机器人就是不在线」而完全无从下手。
  Future<bool> isServiceRunning() => _bridge.isRunning();

  /// 打开系统电池优化设置页。
  Future<void> openBatteryOptimizationSettings() =>
      _bridge.openBatteryOptimizationSettings();

  /// 是否已获得精确闹钟权限。
  ///
  /// 它决定「应用被清掉后能不能自动回来」：精确闹钟在官方后台启动豁免清单里，
  /// 不精确闹钟不在——后者到点也可能因为后台启动被拒而拉不起服务。
  Future<bool> canScheduleExactAlarms() => _bridge.canScheduleExactAlarms();

  /// 打开精确闹钟授权页。
  Future<void> openExactAlarmSettings() => _bridge.openExactAlarmSettings();

  /// 释放监听。
  ///
  /// 与 [detach] 的区别：这里只摘监听，不动服务状态，
  /// 用于测试或重建协调器的场景。
  @override
  void dispose() {
    _bots.removeListener(_onChanged);
    _registry.removeListener(_onChanged);
    super.dispose();
  }

  /// 通知界面（已脱离时不再通知，否则会在 dispose 之后触发而抛异常）。
  void _notify() {
    if (_detached) return;
    notifyListeners();
  }

  void _onChanged() => unawaited(_sync(trigger: '状态变化'));

  /// 应用退出前调用：撤掉前台服务，但**保留用户开关**。
  ///
  /// 不能改用 [setEnabled]（false）来收尾：那会把 `keep_alive_enabled`
  /// 写盘为 false，于是「退出过一次应用」等于永久关掉保活，
  /// 下次冷启动静默失效，用户完全不知道为什么。
  /// 这里只动原生侧，不碰持久化。
  Future<void> detach() async {
    _detached = true;
    dispose();
    _lastApplied = null;
    try {
      await _bridge.stop();
    } catch (error) {
      _log.warn(LogSource.system, '撤掉保活服务失败：$error');
    }
  }

  /// 对齐原生侧的服务状态。
  ///
  /// [trigger] 只用于日志，方便回答「是什么时候、因为什么被关掉的」。
  /// [force] 为 `true` 时跳过「文案没变就不下发」的短路，用于补救性的重试。
  Future<void> _sync({required String trigger, bool force = false}) async {
    if (_detached) return;

    final desired = _enabled && _bots.enabledBots.isNotEmpty
        ? _notificationText()
        : null;
    if (!force && desired == _lastApplied) return;
    _lastApplied = desired;

    try {
      if (desired == null) {
        await _bridge.stop();
        if (_enabled) {
          _log.info(
            LogSource.system,
            '已停止后台保活（当前没有启用的机器人）',
            detail: '触发：$trigger。保活只在有启用的机器人时才有意义。',
          );
        } else {
          _log.info(LogSource.system, '已关闭后台保活', detail: '触发：$trigger。');
        }
        _notify();
        return;
      }

      final started = await _bridge.start(desired);
      if (started) {
        _log.info(
          LogSource.system,
          '后台保活已开启：$desired',
          detail: '触发：$trigger。保活通过前台服务实现，'
              '作用是让进程脱离 cached 状态、不被系统冻结——'
              '否则心跳会停发，网关会把连接关掉。',
        );
      } else {
        _log.warn(
          LogSource.system,
          '后台保活未能开启，网关可能在后台被断开',
          detail: '触发：$trigger。'
              '${_bridge.isSupported ? '常见原因：系统拒绝从后台启动前台服务。'
                  '把应用切到前台会自动重试；'
                  '另外建议在系统设置里把本应用加入电池优化白名单。'
                  : '当前平台不支持前台服务保活。'}',
        );
      }
    } catch (error) {
      _log.error(
        LogSource.system,
        '后台保活操作失败：$error',
        detail: '触发：$trigger。',
      );
    }
    // 无论成功与否都通知一次：界面要能显示「开关是开的但服务没起来」。
    _notify();
  }

  /// 常驻通知的文案。
  ///
  /// 写成「有几个在线」而不是静止的「正在运行」：用户从通知就能判断
  /// 机器人是不是掉线了，不需要点进应用。
  String _notificationText() {
    final online = _registry.onlineCount;
    final total = _bots.enabledBots.length;
    if (online <= 0) return '正在连接网关（已启用 $total 个机器人）';
    if (online >= total) return '$online 个机器人在线';
    return '$online / $total 个机器人在线';
  }
}
