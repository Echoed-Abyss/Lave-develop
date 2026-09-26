import 'package:flutter/foundation.dart';

import '../../api/bot_message_service.dart';
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
  });

  /// 触发指令的原始消息。
  final QqMessage message;

  /// 指令参数（按空白切分，不含指令名本身）。
  final List<String> args;

  /// 引擎本身，便于 `#help` 列出全部指令。
  final CommandEngine engine;

  /// 会话所在场景。
  ConversationScope get scope => message.scope;

  /// 参数是否为空。
  bool get hasArgs => args.isNotEmpty;
}

/// 指令引擎。
///
/// 需求要求「内置简单指令解析，例如 `#help`，可扩展」。
/// 设计要点：
/// 1. **注册表驱动**：新增指令只需在 [builtIns] 里加一条，不改解析逻辑；
/// 2. **遵守被动回复窗口**：官方给的窗口是群聊 5 分钟 / 单聊 60 分钟，
///    超过后被动回复必然失败（40034128）。这里在回复前先判定，
///    窗口已关闭时**不静默改发主动消息**——主动消息受独立频控且会打扰用户，
///    应交给用户显式决定，因此只记一条警告日志；
/// 3. **每次回复递增 `msg_seq`**：由 [MessageSender] 内部处理。
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
    if (!message.canReplyAt(now)) {
      // 窗口关闭时不擅自改发主动消息：那会消耗独立频控额度并主动打扰用户。
      _log.warn(
        LogSource.event,
        '被动回复窗口已关闭，$prefix${spec.name} 的回复未发送',
        botId: message.botId,
        detail: '官方窗口：群聊 ${QqLimits.groupReplyWindow.inMinutes} 分钟 / '
            '单聊 ${QqLimits.c2cReplyWindow.inMinutes} 分钟；'
            '如需主动发送请到消息面板手动操作。',
      );
      return true;
    }

    final ApiResponse response = await sender.sendText(
      conversationId: message.conversationId,
      scope: message.scope,
      text: reply,
      passive: true,
      msgId: message.wireId,
      eventId: message.eventId,
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
          '剩余被动回复 ${invocation.message.remainingRepliesAt(DateTime.now())} 次）',
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
            '${message.remainingRepliesAt(now)} / ${message.maxReplies}';
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
