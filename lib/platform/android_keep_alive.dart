import 'package:flutter/services.dart';

import '../core/logging/app_logger.dart';

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
