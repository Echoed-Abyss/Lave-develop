import 'package:flutter/foundation.dart';

/// WSS 协议相关的枚举与常量。
///
/// 全部逐字对照官方文档，见 `docs/qq-bot/knowledge-base.html` 第 3.4 / 4 / 10.1 节。

/// 官方 OpCode 全集。
///
/// **官方只定义了 0、1、2、6、7、9、10、11、12、13 这十三个取值**，
/// 3 / 4 / 5 / 8 在官方文档中没有任何定义。因此本枚举刻意不覆盖它们，
/// 由 `QqOpCode.fromValue` 返回 `null`，调用方记录原始 op 后忽略该帧——
/// 这样将来官方新增 op 也不会让连接层崩溃。
enum QqOpCode {
  /// 服务端推送消息（webhook / websocket 共用）。
  dispatch(0, 'Dispatch'),

  /// 心跳，客户端或服务端发送。
  heartbeat(1, 'Heartbeat'),

  /// 客户端发送鉴权。
  identify(2, 'Identify'),

  /// 客户端恢复连接。
  resume(6, 'Resume'),

  /// 服务端通知客户端重新连接。
  reconnect(7, 'Reconnect'),

  /// identify 或 resume 参数有错时返回。
  invalidSession(9, 'Invalid Session'),

  /// 建连后网关下发的第一条消息，含心跳周期。
  hello(10, 'Hello'),

  /// 心跳发送成功后的回执。
  heartbeatAck(11, 'Heartbeat ACK'),

  /// 仅 HTTP 回调模式的回包。
  httpCallbackAck(12, 'HTTP Callback ACK'),

  /// 仅 HTTP 回调模式的回调地址验证。
  callbackUrlVerify(13, '回调地址验证');

  const QqOpCode(this.value, this.label);

  final int value;
  final String label;

  /// 按官方数值解析。未知取值返回 `null`，调用方应记录原始值后忽略。
  static QqOpCode? fromValue(int? raw) {
    if (raw == null) return null;
    for (final op in values) {
      if (op.value == raw) return op;
    }
    return null;
  }

  /// 该 op 是否与 WebSocket 接入相关（12 / 13 仅供 HTTP 回调模式使用）。
  bool get isWebSocketOp => this != httpCallbackAck && this != callbackUrlVerify;
}

/// 代理对 WSS 关闭码的推荐动作。
///
/// 直接由官方错误码表的「是否可以重试 RESUME / 是否可以重试 IDENTIFY」两列折算而来，
/// 是连接恢复层唯一的决策输入。
enum WsRecoveryAction {
  /// 可以重新发起 Resume（官方：4008 / 4009）。
  resume,

  /// 必须重新发起 Identify，旧 session 作废（官方：4006 / 4007 / 4900~4913）。
  identify,

  /// 两个都不可重试，属于代码或权限问题，或机器人处于终态，需人工介入。
  fatal,
}

/// 关闭码解析结果。
///
/// 把官方错误码表的一行（值 / 含义 / 可否 RESUME / 可否 IDENTIFY）变成一个可直接使用的对象。
@immutable
class QqWsCloseInfo {
  const QqWsCloseInfo({
    required this.code,
    required this.message,
    required this.action,
    required this.known,
  });

  /// 官方关闭码数值。
  final int code;

  /// 官方对该码的中文含义描述。
  final String message;

  /// 官方建议的恢复动作。
  final WsRecoveryAction action;

  /// 是否为官方表中列出的已知码。
  ///
  /// 未知码（例如官方新增、或 TCP 层中断产生的非 4xxx 码）一律按 [WsRecoveryAction.fatal]
  /// 处理过于激进，因此这里保留标记，由恢复层决定是否按网络异常重连。
  final bool known;

  /// 机器人已封禁。官方要求断开连接并申请解封后再连接。
  bool get isBanned => code == 4915;

  /// 机器人已下架，只允许连接沙箱环境。
  bool get isOfflineSandboxOnly => code == 4914;

  /// 是否为需要人工修正的终态（封禁 / 下架）。
  bool get isTerminal => isBanned || isOfflineSandboxOnly;

  /// 恢复层应当采用的动作。
  ///
  /// 对官方表中**未收录**的关闭码（含标准关闭码、以及官方表中编号不连续的
  /// 4003~4005），不能按 [WsRecoveryAction.fatal] 处理——那会让一次普通的
  /// 网络断开变成「永久停止重连」。因此这类码统一按网络断开处理：
  /// 退避重连并尝试 Resume。
  WsRecoveryAction get effectiveAction =>
      known ? action : WsRecoveryAction.resume;

  /// 官方表中 4900~4913 为一整段「内部错误，请重连」，可重试 IDENTIFY。
  ///
  /// 该段在官方表中以范围形式给出，无法用枚举逐条列举，故单独判定。
  static bool isInternalError(int code) => code >= 4900 && code <= 4913;

  /// 解析关闭码。
  ///
  /// 未知码返回 [known] 为 `false` 的结果并保留服务端给的描述，
  /// 绝不抛异常——关闭码解析失败本身不应该再制造一次失败。
  static QqWsCloseInfo resolve(int rawCode, {String? reason}) {
    // 官方表中以范围给出的「内部错误」段优先判定。
    if (isInternalError(rawCode)) {
      return QqWsCloseInfo(
        code: rawCode,
        message: '内部错误，请重连',
        action: WsRecoveryAction.identify,
        known: true,
      );
    }

    final entry = _lookup(rawCode);
    if (entry != null) {
      return QqWsCloseInfo(
        code: rawCode,
        message: entry.message,
        action: entry.action,
        known: true,
      );
    }

    final hasReason = reason != null && reason.trim().isNotEmpty;
    return QqWsCloseInfo(
      code: rawCode,
      message: hasReason
          ? '未知关闭码（服务端描述：${reason.trim()}），按网络断开处理'
          : '未知关闭码，按网络断开处理',
      action: WsRecoveryAction.fatal,
      known: false,
    );
  }

  /// 官方 WebSocket 错误码表（不含以范围表示的 4900~4913）。
  ///
  /// 逐条对应官方「值 / 含义」两列；`action` 由官方的
  /// 「是否可以重试 RESUME」「是否可以重试 IDENTIFY」两列折算：
  /// - 只有 IDENTIFY 可重试 → [WsRecoveryAction.identify]
  /// - RESUME 可重试 → [WsRecoveryAction.resume]
  /// - 两个都不可重试 → [WsRecoveryAction.fatal]
  static ({String message, WsRecoveryAction action})? _lookup(int code) =>
      switch (code) {
        4001 => (
            message: '无效的 opcode',
            action: WsRecoveryAction.fatal,
          ),
        4002 => (
            message: '无效的 payload',
            action: WsRecoveryAction.fatal,
          ),
        4006 => (
            message: '无效的 session id，无法继续 resume，请 identify',
            action: WsRecoveryAction.identify,
          ),
        4007 => (
            message: 'seq 错误',
            action: WsRecoveryAction.identify,
          ),
        4008 => (
            message: '发送 payload 过快，请重新连接，并遵守连接后返回的频控信息',
            action: WsRecoveryAction.resume,
          ),
        4009 => (
            message: '连接过期，请重连并执行 resume 进行重新连接',
            action: WsRecoveryAction.resume,
          ),
        4010 => (
            message: '无效的 shard',
            action: WsRecoveryAction.fatal,
          ),
        4011 => (
            message: '连接需要处理的 guild 过多，请进行合理的分片',
            action: WsRecoveryAction.fatal,
          ),
        4012 => (
            message: '无效的 version',
            action: WsRecoveryAction.fatal,
          ),
        4013 => (
            message: '无效的 intent',
            action: WsRecoveryAction.fatal,
          ),
        4014 => (
            message: 'intent 无权限',
            action: WsRecoveryAction.fatal,
          ),
        4914 => (
            message: '机器人已下架，只允许连接沙箱环境，请断开连接，检验当前连接环境',
            action: WsRecoveryAction.fatal,
          ),
        4915 => (
            message: '机器人已封禁，不允许连接，请断开连接，申请解封后再连接',
            action: WsRecoveryAction.fatal,
          ),
        _ => null,
      };
}

/// 官方 intents 位定义。
///
/// **全部按官方给出的位移表达式书写**，刻意不写换算后的十进制常量：
/// 官方全站只提供 `1 << n` 形式的表达式与「该位对应哪些事件」的清单，
/// 从未给出数值对照表。写成表达式可以让代码与官方唯一权威表述保持一致，
/// 也避免有人误以为那些换算值是官方原文。
abstract final class QqIntents {
  /// 频道（Guild）基础事件：GUILD_* / CHANNEL_*。基础事件，默认有订阅权限。
  static const int guilds = 1 << 0;

  /// 频道成员事件：GUILD_MEMBER_*。基础事件，默认有订阅权限。
  static const int guildMembers = 1 << 1;

  /// 频道全部消息事件：MESSAGE_CREATE / MESSAGE_DELETE。
  ///
  /// 官方注明**仅私域机器人**能够设置此 intents；传了无权限的位会导致网关
  /// 直接报错并关闭连接。
  static const int guildMessages = 1 << 9;

  /// 频道表情表态事件：MESSAGE_REACTION_ADD / MESSAGE_REACTION_REMOVE。
  static const int guildMessageReactions = 1 << 10;

  /// 频道私信事件：DIRECT_MESSAGE_CREATE / DIRECT_MESSAGE_DELETE。
  static const int directMessage = 1 << 12;

  /// 群成员事件：GROUP_MEMBER_ADD / GROUP_MEMBER_REMOVE / GROUP_JOIN_REQUEST。
  ///
  /// **注意官方文档内部不一致**：该位未出现在官方 intents 清单里，
  /// 只出现在各群成员事件页的 Intent 字段中。因此属于「需真机实测确认」项，
  /// 若鉴权时收到 4014（intent 无权限）应降级为 [defaultMaskWithoutGroupMembers]。
  static const int groupMemberEvent = 1 << 24;

  /// 单聊与群聊事件（本项目核心）：C2C_MESSAGE_CREATE、GROUP_AT_MESSAGE_CREATE、
  /// GROUP_ADD_ROBOT、GROUP_DEL_ROBOT、FRIEND_ADD、FRIEND_DEL、
  /// C2C_MSG_RECEIVE/REJECT、GROUP_MSG_RECEIVE/REJECT。
  static const int groupAndC2cEvent = 1 << 25;

  /// 互动事件：INTERACTION_CREATE（消息按钮、快捷菜单、消息反馈、授权等）。
  static const int interaction = 1 << 26;

  /// 消息审核事件：MESSAGE_AUDIT_PASS / MESSAGE_AUDIT_REJECT。
  static const int messageAudit = 1 << 27;

  /// 论坛事件。官方注明**仅私域机器人**能够设置。
  static const int forumsEvent = 1 << 28;

  /// 音频动作事件：AUDIO_START / AUDIO_FINISH / AUDIO_ON_MIC / AUDIO_OFF_MIC。
  static const int audioAction = 1 << 29;

  /// 频道公域消息事件：AT_MESSAGE_CREATE / PUBLIC_MESSAGE_DELETE。基础事件，默认有权限。
  static const int publicGuildMessages = 1 << 30;

  /// 本项目默认订阅掩码：单聊 + 群聊 + 互动 + 群成员。
  ///
  /// 只放本项目真正要用到的位。官方明确警告「请开发者注意订阅事件的范围需要控制在
  /// 自己所需要的范围之内」——多放的位一旦无权限，连接会被直接关闭。
  static const int defaultMask =
      groupAndC2cEvent | interaction | groupMemberEvent;

  /// 降级掩码：去掉归属存疑的 [groupMemberEvent]，用于 4014 后的自动降级重连。
  static const int defaultMaskWithoutGroupMembers =
      groupAndC2cEvent | interaction;

  /// 判断某个掩码是否包含指定位。
  static bool has(int mask, int bit) => (mask & bit) == bit;
}
