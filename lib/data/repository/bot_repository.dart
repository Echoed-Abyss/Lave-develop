import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/app_config.dart';
import '../../core/error/app_error.dart';
import '../../domain/models/bot_profile.dart';

/// 会话水位（`session_id` 与 `seq`）的持久化模型。
///
/// 官方推荐「处理过事件之后记录下 `s`」，这样 Resume 时网关会自动补发
/// 该 seq 之后的事件。**进程被杀后如果这两个值丢了，断线期间的事件
/// 就只能靠重新 Identify 补救，而那会丢掉这段窗口内的全部事件。**
@immutable
class SessionRecord {
  const SessionRecord({
    required this.botId,
    this.sessionId,
    this.seq,
    this.updatedAt,
  });

  final String botId;
  final String? sessionId;
  final int? seq;
  final DateTime? updatedAt;

  /// 是否具备 Resume 条件（官方 Resume 需要 session_id + seq）。
  bool get canResume =>
      sessionId != null && sessionId!.isNotEmpty && seq != null;

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        botId: (json['bot_id'] as String?) ?? '',
        sessionId: json['session_id'] as String?,
        seq: (json['seq'] as num?)?.toInt(),
        updatedAt: DateTime.tryParse((json['updated_at'] as String?) ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'bot_id': botId,
        if (sessionId != null) 'session_id': sessionId,
        if (seq != null) 'seq': seq,
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };
}

/// 机器人账号与会话水位的仓库。
///
/// 账号信息（非密钥部分）走普通 JSON 文件；密钥走 [CredentialStore]。
/// 两者分开是刻意的：把密钥和普通配置混在同一个存储里，
/// 迟早会有人为了「导出一份配置」而把密钥一起带出去。
class BotRepository extends ChangeNotifier {
  BotRepository({required BotStoreLike store, required AppConfig config})
      : _store = store,
        _config = config;

  final BotStoreLike _store;
  final AppConfig _config;

  final List<BotProfile> _bots = [];
  final Map<String, SessionRecord> _sessions = {};
  final Map<String, DateTime> _lastConnected = {};

  /// 全部机器人账号（按添加顺序）。
  List<BotProfile> get bots => List.unmodifiable(_bots);

  /// 已启用的机器人。
  List<BotProfile> get enabledBots =>
      _bots.where((b) => b.enabled).toList(growable: false);

  /// 是否还没有任何账号（界面据此显示引导页）。
  bool get isEmpty => _bots.isEmpty;

  /// 是否已达并发上限。
  ///
  /// 并发上限来自 `AppConfig.maxConcurrentConnections`（默认 3）：
  /// 每条连接都要独立跑心跳、独立保存会话、独立重连，
  /// 数量上去后耗电与内存是主要成本。
  bool get reachedConcurrencyLimit =>
      enabledBots.length >= _config.maxConcurrentConnections;

  /// 按 AppID 查找。
  BotProfile? find(String appId) {
    for (final bot in _bots) {
      if (bot.appId == appId) return bot;
    }
    return null;
  }

  /// 添加账号。已存在时返回 `false`。
  Future<bool> add(BotProfile profile) async {
    if (profile.appId.isEmpty) return false;
    if (find(profile.appId) != null) return false;
    _bots.add(profile);
    await _persist();
    return true;
  }

  /// 更新账号。
  Future<void> update(BotProfile profile) async {
    final index = _bots.indexWhere((b) => b.appId == profile.appId);
    if (index < 0) return;
    _bots[index] = profile;
    await _persist();
  }

  /// 写入官方返回的机器人资料（昵称与头像）。
  ///
  /// 与 [update] 分开是刻意的：调用方是「后台资料刷新」，不是用户编辑。
  /// 它只应改动这两个官方字段，绝不能碰到用户填的备注名与启用状态——
  /// 用 [update] 直接整体覆盖的话，一次刷新就会把备注名清掉。
  ///
  /// 内容没变时不落盘：应用每次启动都会刷一遍资料，
  /// 无变化也写一次纯属浪费（写的是整个文档）。
  Future<void> updateIdentity(
    String appId, {
    String? officialName,
    String? avatarUrl,
  }) async {
    final bot = find(appId);
    if (bot == null) return;

    final name = (officialName == null || officialName.isEmpty) ? null : officialName;
    final avatar = (avatarUrl == null || avatarUrl.isEmpty) ? null : avatarUrl;
    if (bot.officialName == name && bot.avatarUrl == avatar) return;

    await update(
      bot.copyWith(
        officialName: name ?? bot.officialName,
        avatarUrl: avatar ?? bot.avatarUrl,
      ),
    );
  }

  /// 删除账号（含其会话水位）。密钥由调用方负责删除。
  Future<void> remove(String appId) async {
    _bots.removeWhere((b) => b.appId == appId);
    _sessions.remove(appId);
    _lastConnected.remove(appId);
    await _persist();
  }

  /// 切换启用状态。
  ///
  /// 返回错误：达到并发上限时拒绝启用，并给出可读原因，
  /// 而不是静默失败。
  Future<AppError?> setEnabled(String appId, bool enabled) async {
    final bot = find(appId);
    if (bot == null) return null;
    if (enabled && !bot.enabled && reachedConcurrencyLimit) {
      return UnknownApiError(
        userMessage: '同时在线数量已达上限'
            '（${_config.maxConcurrentConnections} 个），'
            '请先关闭其他机器人再启用。',
      );
    }
    await update(bot.copyWith(enabled: enabled));
    return null;
  }

  /// 记录一次连接成功。
  Future<void> markConnected(String appId, DateTime at) async {
    _lastConnected[appId] = at;
    await update(find(appId)?.copyWith(lastConnectedAt: at) ??
        BotProfile(appId: appId, displayName: appId));
  }

  /// 读取会话水位。
  SessionRecord session(String appId) =>
      _sessions[appId] ?? SessionRecord(botId: appId);

  /// 保存会话水位。
  ///
  /// 刻意**不**在每次推进 seq 时都落盘（事件量大时会造成 IO 抖动），
  /// 由调用方控制频率；但 session_id 变化时必须立刻落盘。
  Future<void> saveSession(
    String botId, {
    String? sessionId,
    int? seq,
  }) async {
    final current = session(botId);
    _sessions[botId] = SessionRecord(
      botId: botId,
      sessionId: sessionId ?? current.sessionId,
      seq: seq ?? current.seq,
      updatedAt: DateTime.now(),
    );
    await _persist();
  }

  /// 清空会话（Identify 重新开始时，旧 session 作废）。
  Future<void> clearSession(String botId) async {
    _sessions[botId] = SessionRecord(botId: botId);
    await _persist();
  }

  /// 从本地载入。
  Future<void> restore() async {
    try {
      final botItems = await _store.readList('bots');
      _bots
        ..clear()
        ..addAll(botItems.map(BotProfile.fromJson).where((b) => b.appId.isNotEmpty));

      final sessionItems = await _store.readList('sessions');
      _sessions
        ..clear()
        ..addEntries(
          sessionItems
              .map(SessionRecord.fromJson)
              .where((s) => s.botId.isNotEmpty)
              .map((s) => MapEntry(s.botId, s)),
        );
    } catch (_) {
      // 本地数据损坏不应导致应用打不开：忽略并按空列表继续。
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    notifyListeners();
    await _store.writeList(
      'bots',
      _bots.map((b) => b.toJson()).toList(),
    );
    await _store.writeList(
      'sessions',
      _sessions.values.map((s) => s.toJson()).toList(),
    );
  }
}

/// 机器人存储的最小依赖面（便于测试替换）。
abstract interface class BotStoreLike {
  Future<List<Map<String, dynamic>>> readList(String key);

  Future<void> writeList(String key, List<Map<String, dynamic>> items);
}
