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

/// 可选的 intents 增量位。
///
/// **这是本项目最需要谨慎处理的一处**：官方原文明确
/// 「如果在鉴权的时候传递了无权限的 `intents`，`websocket` 会报错，
/// 并直接关闭连接」。而官方基础事件（默认有权限）只有
/// `GUILDS`、`PUBLIC_GUILD_MESSAGES`、`GUILD_MEMBERS` 三位，
/// 其余都需要经过申请。
///
/// 也就是说：**多传一位就可能让连接根本建不起来**，症状是
/// 「一直重连、日志里看不到任何事件」——很容易被误判成网络问题。
///
/// 因此这里把每个可选的位移单独建模，并标注它是否出现在官方 intents 清单里，
/// 由用户在界面上逐个确认后再打开，而不是一次性全塞进默认掩码。
enum QqOptionalIntent {
  /// 互动事件（消息按钮、快捷菜单、授权、反馈）。官方清单中有此位。
  ///
  /// 覆盖事件：`INTERACTION_CREATE`。
  interaction(
    QqIntents.interaction,
    'INTERACTION',
    '互动事件（消息按钮、快捷菜单、授权）',
    inOfficialList: true,
  ),

  /// 群成员变动（加群、退群、加群申请）。
  ///
  /// **该位不在官方 intents 清单中**：它只出现在若干群成员事件页的
  /// 「Intent」字段说明里，官方总表从未列出 `1 << 24`。
  /// 属于「官方文档内部不一致」项，因此默认关闭，并提示用户风险。
  groupMemberEvent(
    QqIntents.groupMemberEvent,
    'GROUP_MEMBER_EVENT',
    '群成员变动（加群 / 退群 / 加群申请）',
    inOfficialList: false,
  );

  const QqOptionalIntent(
    this.bit,
    this.officialName,
    this.description, {
    required this.inOfficialList,
  });

  /// 位移值。
  final int bit;

  /// 官方名称（官方总表或事件页中使用的写法）。
  final String officialName;

  /// 中文说明。
  final String description;

  /// 是否出现在官方 intents 清单里。
  ///
  /// `false` 表示官方总表没有列出该位，开启后有可能被网关判定为
  /// 「无权限的 intents」而直接关闭连接——必须在界面上提示这一点。
  final bool inOfficialList;

  /// 解析。
  static QqOptionalIntent? fromName(String? name) {
    for (final item in values) {
      if (item.name == name) return item;
    }
    return null;
  }
}

/// 官方 error code 4014 的提示构造器（供界面直接展示该怎么做）。
String intentRejectedHint(int attemptedMask, int fallbackMask) {
  final removed = attemptedMask & ~fallbackMask;
  final buffer = StringBuffer()
    ..writeln('网关拒绝了本次事件订阅（官方 4014：intent 无权限），已自动降级重试。')
    ..writeln('被移除的位：$removed');
  for (final item in QqOptionalIntent.values) {
    if ((removed & item.bit) != 0) {
      buffer.writeln(
        '  · ${item.officialName}（${item.description}）'
        '${item.inOfficialList ? '' : ' ← 该位不在官方 intents 清单中，风险最高'}',
      );
    }
  }
  buffer.write('若需要这些能力，请到 QQ 开放平台后台申请对应权限后再开启。');
  return buffer.toString();
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
  /// **该位不在官方 intents 清单中**（官方总表只列到
  /// `GROUP_AND_C2C_EVENT (1<<25)`、`INTERACTION (1<<26)` 等，
  /// 从未出现 `1 << 24`）；它只出现在若干群成员事件页的「Intent」字段说明里。
  ///
  /// 由于官方明确「传递了无权限的 intents 会报错并直接关闭连接」，
  /// 这个位**默认关闭**，由用户在设置页显式开启。见 [QqOptionalIntent]。
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

  /// 本项目必需的最小订阅掩码：**只有一位**。
  ///
  /// 这一位覆盖本项目全部核心能力：单聊消息、群 @消息、机器人进出群、
  /// 好友增删、主动消息开关变更。
  static const int minimal = groupAndC2cEvent;

  /// 默认订阅掩码 ＝ [minimal]。
  ///
  /// **刻意只含一位，这是本项目的一处关键修复。**
  /// 官方原文：「如果在鉴权的时候传递了无权限的 `intents`，`websocket` 会报错，
  /// 并直接关闭连接」，且「除了 GUILDS、PUBLIC_GUILD_MESSAGES、GUILD_MEMBERS
  /// 是基础事件默认有权限之外，其他的特殊事件都需要经过申请」。
  ///
  /// 早期版本把 `interaction` 与归属存疑的 `groupMemberEvent` 一并塞进默认掩码，
  /// 后果是 Identify 被拒、连接被立即关闭、客户端反复重连，
  /// **表现就是「连上了但永远收不到任何消息」**——而且日志里看不到事件，
  /// 极易被误判为网络问题。现在默认只发必需位，其余由用户按权限自行开启。
  static const int defaultMask = minimal;

  /// 降级掩码：去掉全部可选位，退回 [minimal]。
  ///
  /// 用于收到官方 4014（intent 无权限）时的自动降级重连。
  static const int degraded = minimal;

  /// 依据用户勾选的可选位构造掩码。
  static int maskWith(Iterable<QqOptionalIntent> extras) {
    var mask = minimal;
    for (final extra in extras) {
      mask |= extra.bit;
    }
    return mask;
  }

  /// 把掩码拆回可选位集合（用于界面回显与降级时判断去掉了哪些位）。
  static Set<QqOptionalIntent> extrasOf(int mask) {
    final result = <QqOptionalIntent>{};
    for (final item in QqOptionalIntent.values) {
      if (has(mask, item.bit)) result.add(item);
    }
    return result;
  }

  /// 去掉全部可选位，得到降级掩码。
  static int removeOptional(int mask) {
    for (final item in QqOptionalIntent.values) {
      mask &= ~item.bit;
    }
    return mask;
  }

  /// 判断某个掩码是否包含指定位。
  static bool has(int mask, int bit) => (mask & bit) == bit;
}
