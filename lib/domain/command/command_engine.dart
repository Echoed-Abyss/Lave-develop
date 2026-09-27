import 'package:flutter/foundation.dart';

import '../../api/bot_message_service.dart';
import '../../api/dto/send_message_request.dart';
import '../../api/qq_http_client.dart';
import '../../core/constants/qq_limits.dart';
import '../../core/logging/log_service.dart';
import '../models/log_entry.dart';
import '../models/qq_enums.dart';
import '../models/qq_message.dart';

/// 一条可执行指令。
@immutable
class CommandSpec {
  const CommandSpec({
    required this.name,
    required this.usage,
    required this.description,
    required this.handler,
  });

  /// 指令名（不含前缀 `#`）。
  final String name;

  /// 用法示例。
  final String usage;

  /// 说明文本。
  final String description;

  /// 处理函数。返回要回复的文本（`null` 表示不回复）。
  final String? Function(CommandInvocation invocation) handler;
}

/// 一次指令调用的上下文。
@immutable
class CommandInvocation {
  const CommandInvocation({
    required this.message,
    required this.args,
    required this.engine,
    this.repliesUsed = 0,
  });

  /// 触发指令的原始消息。
  final QqMessage message;

  /// 指令参数（按空白切分，不含指令名本身）。
  final List<String> args;

  /// 引擎本身，便于 `#help` 列出全部指令。
  final CommandEngine engine;

  /// 本条消息**已经用掉**的被动回复次数。
  ///
  /// 由发送层（`msg_seq` 计数器）实时给出，而不是读 [QqMessage.repliesUsed]：
  /// 后者是持久化字段，进程重启后与真实用量不同步，拿它做展示会一直显示
  /// 「剩余满额」，用户按提示连续回复到第 6 次时才被服务端拒绝。
  final int repliesUsed;

  /// 会话所在场景。
  ConversationScope get scope => message.scope;

  /// 参数是否为空。
  bool get hasArgs => args.isNotEmpty;

  /// 本条消息还剩几次被动回复。
  int get remainingReplies =>
      (message.maxReplies - repliesUsed).clamp(0, message.maxReplies);
}

/// 指令引擎。
///
/// 需求要求「内置简单指令解析，例如 `#help`，可扩展」。设计要点：
/// 1. **注册表驱动**：新增指令只需在 [builtIns] 里加一条，不改解析逻辑；
/// 2. **回复一律用 `msg_id`**：官方把被动消息分成「回复用户消息（`msg_id`）」
///    与「响应事件（`event_id`）」两条互斥路径，而指令回复属于前者。
///    取凭据统一走 [QqMessage.replyCredential]，杜绝「两个 id 都填」的非法请求；
/// 3. **被动回复不可用时改发主动消息**：窗口（群 5 分钟 / 单聊 60 分钟）
///    已关闭、次数用尽、或事件里没有消息 id 时，仍然把回复发出去——
///    主动消息是官方支持的正常路径，只是受独立频控约束。
///    每次降级都会写一条 WARN，说明降级原因，避免用户以为「被动回复生效了」；
/// 4. **每次回复递增 `msg_seq`**：由 [MessageSender] 内部处理。
class CommandEngine {
  CommandEngine({required LogService log}) : _log = log {
    for (final spec in builtIns) {
      _registry[spec.name] = spec;
    }
  }

  final LogService _log;
  final Map<String, CommandSpec> _registry = {};

  /// 指令前缀。官方文档未对指令格式做任何规定，`#` 只是本项目约定。
  static const String prefix = '#';

  /// 全部已注册指令。
  List<CommandSpec> get commands => _registry.values.toList(growable: false);

  /// 注册自定义指令（供插件或业务扩展）。
  void register(CommandSpec spec) => _registry[spec.name] = spec;

  /// 尝试把一条消息当作指令处理。
  ///
  /// 返回 `true` 表示「这是一条指令，已被消费」（无论是否成功回复）；
  /// 返回 `false` 表示不是指令，调用方可以继续交给插件处理。
  Future<bool> tryHandle(QqMessage message, MessageSender sender) async {
    if (!message.isIncoming) return false;
    final parsed = parse(message.content);
    if (parsed == null) return false;

    final spec = _registry[parsed.name];
    if (spec == null) {
      _log.warn(
        LogSource.event,
        '收到未知指令：$prefix${parsed.name}（可用 ${prefix}help 查看全部指令）',
        botId: message.botId,
      );
      return true;
    }

    final invocation = CommandInvocation(
      message: message,
      args: parsed.args,
      engine: this,
      // 实时用量以发送层的 msg_seq 计数器为准（模型上的字段是持久化快照）。
      repliesUsed: sender.repliesUsedFor(message.wireId),
    );

    String? reply;
    try {
      reply = spec.handler(invocation);
    } catch (error) {
      _log.error(
        LogSource.event,
        '指令 $prefix${spec.name} 执行失败',
        botId: message.botId,
        detail: '$error',
      );
      return true;
    }

    if (reply == null || reply.isEmpty) return true;

    final now = DateTime.now();
    // 统一从领域模型取凭据：回复消息恒为 msg_id。
    // 只有当「窗口还在 + 次数没用完 + 有消息 id」三者同时成立时才是被动回复。
    final PassiveCredential? credential =
        message.canReplyAt(now) && invocation.repliesUsed < message.maxReplies
            ? message.replyCredential
            : null;

    if (credential == null) {
      // 被动回复这条路已经不可用，改发主动消息。
      //
      // 不在这里放弃回复：主动消息是官方支持的正常路径（用户已确认可用），
      // 但它的约束与被回复完全无关——受独立频控，且用户可在 QQ 客户端
      // 关闭「允许主动发送」。因此必须留一条 WARN 说明降级原因，
      // 否则用户会以为被动回复生效了，之后排查「为什么消息发出去了」时无从下手。
      _log.warn(
        LogSource.event,
        '$prefix${spec.name} 的回复降级为主动消息发送（被动回复不可用）',
        botId: message.botId,
        detail: _whyNotPassive(message, invocation.repliesUsed, now),
      );
    }

    final ApiResponse response = await sender.sendText(
      conversationId: message.conversationId,
      scope: message.scope,
      text: reply,
      credential: credential,
    );

    if (!response.isSuccess) {
      final error = response.failure!;
      _log.error(
        LogSource.event,
        '指令回复发送失败：${error.userMessage}',
        botId: message.botId,
        officialCode: error.officialCode,
        traceId: error.traceId,
      );
    }
    return true;
  }

  /// 说明「为什么这次没能走被动回复」。
  ///
  /// 单独抽出来是因为降级原因有三种且措辞差别大，
  /// 混在日志拼接里很容易变成一句没有信息量的「发送失败」。
  static String _whyNotPassive(QqMessage message, int used, DateTime now) {
    final reasons = <String>[];
    if (!message.canReplyAt(now)) {
      reasons.add(
        '被动回复已过有效期（官方窗口：群聊 '
        '${QqLimits.groupReplyWindow.inMinutes} 分钟 / '
        '单聊 ${QqLimits.c2cReplyWindow.inMinutes} 分钟）',
      );
    }
    if (used >= message.maxReplies) {
      reasons.add('本消息的被动回复次数已用尽（上限 ${message.maxReplies} 次）');
    }
    if (message.replyCredential == null) {
      reasons.add('事件里没有携带消息 id（msg_id），没有可回复的目标');
    }
    if (reasons.isEmpty) reasons.add('未满足被动回复条件');

    return '${reasons.join('；')}。'
        '主动消息受独立频控约束，且用户可在 QQ 客户端关闭「允许主动发送」，'
        '关闭后发送会失败。';
  }

  /// 解析指令文本。
  ///
  /// 返回 `null` 表示不是指令（不含前缀，或前缀后为空）。
  static ParsedCommand? parse(String? content) {
    if (content == null) return null;
    final text = content.trim();
    if (!text.startsWith(prefix)) return null;
    final body = text.substring(prefix.length).trim();
    if (body.isEmpty) return null;
    final parts = body.split(RegExp(r'\s+'));
    return ParsedCommand(
      name: parts.first.toLowerCase(),
      args: parts.length > 1 ? parts.sublist(1) : const [],
    );
  }

  /// 内置指令表。
  ///
  /// 刻意只放三条：自用场景下指令越多越难维护，
  /// 真正的业务逻辑应该写在插件里（插件有独立的崩溃隔离与启停控制）。
  static final List<CommandSpec> builtIns = [
    CommandSpec(
      name: 'help',
      usage: '#help',
      description: '列出全部可用指令',
      handler: (invocation) {
        final lines = invocation.engine.commands
            .map((c) => '${c.usage} —— ${c.description}')
            .join('\n');
        return '可用指令：\n$lines';
      },
    ),
    CommandSpec(
      name: 'ping',
      usage: '#ping',
      description: '检测机器人是否在线',
      handler: (invocation) =>
          'pong（${invocation.scope.label}，'
          '剩余被动回复 ${invocation.remainingReplies} 次）',
    ),
    CommandSpec(
      name: 'status',
      usage: '#status',
      description: '查看本会话的回复额度与窗口状态',
      handler: (invocation) {
        final message = invocation.message;
        final now = DateTime.now();
        final deadline = message.replyDeadline;
        final remain = deadline == null ? '未知' : _humanize(deadline.difference(now));
        return '会话状态：\n'
            '场景：${message.scope.label}\n'
            '会话：${message.conversationId}\n'
            '被动回复窗口剩余：$remain\n'
            '本消息剩余可回复次数：'
            '${invocation.remainingReplies} / ${message.maxReplies}\n'
            '（已用 ${invocation.repliesUsed} 次，'
            '超出后会自动改用主动消息发送）';
      },
    ),
  ];

  /// 把时长变成人话。
  static String _humanize(Duration duration) {
    if (duration.isNegative) return '已关闭';
    if (duration.inMinutes >= 1) return '${duration.inMinutes} 分钟';
    return '${duration.inSeconds} 秒';
  }
}

/// 解析结果。
@immutable
class ParsedCommand {
  const ParsedCommand({required this.name, required this.args});

  final String name;
  final List<String> args;
}
