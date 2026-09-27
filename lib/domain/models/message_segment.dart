import 'package:flutter/foundation.dart';

/// 消息正文里的内嵌元素。
///
/// 官方把「@ 某人」「表情」「指令按钮」这类内容以**内嵌标签**的形式写在
/// 消息正文里（`text-chain` 能力，知识库 9.7 节），而不是独立字段。
/// 直接把这些标签原样显示出来的效果很差：群聊里一条
/// `@全体成员 <@CA87605D7C22D7BA4863B86754D1876D>` 会变成一串
/// 32 位十六进制字符，用户根本看不出是谁。
///
/// 官方给出的格式（同一能力有新旧两套写法，旧写法仍在流通）：
///
/// | 能力 | 新格式 | 旧格式 | 生效场景 |
/// | --- | --- | --- | --- |
/// | @某人 | `<qqbot-at-user id="" />` | `<@userid>` | 群聊 |
/// | @全部成员 | `<qqbot-at-everyone />` | `@everyone` | 仅频道 |
/// | 回车指令 | `<qqbot-cmd-enter text="" />` | 无 | 仅 markdown |
/// | 参数指令 | `<qqbot-cmd-input text="" show="" />` | 无 | 仅 markdown |
/// | 跳转子频道 | `<#channel_id>` | 无 | 仅频道 |
/// | 表情 | `<emoji:id>` | 无 | 仅频道 |
///
/// 另外真机上还观察到一种**官方文档里没有**的形式：
/// `<faceType=6,faceId="0",ext="eyJ0ZXh0IjoiIn0=">`。
/// `ext` 是 `{"text":""}` 的 base64。官方没有给出 `faceId` 到表情图片的
/// 映射表，因此本项目只能把它渲染成一个中性标签，不会去猜图片地址。
///
/// 这一层刻意**不引入任何图片资源**：表情、频道这些能力在本项目支持的
/// 单聊 / 群聊场景里其实不可用，出现它们只说明是别的客户端发来的内容，
/// 渲染成可读的标签就够了。
enum MessageSegmentKind {
  /// 普通文字。
  text,

  /// `@某人`。昵称取自事件的 `mentions`，取不到时退化为通用占位。
  mention,

  /// `@全部成员`。
  mentionEveryone,

  /// 表情（含未文档化的 `faceType` 形式）。
  face,

  /// 指令标签（`/xxx`）。
  command,

  /// 子频道引用。
  channel,

  /// 认出是官方内嵌元素，但本项目不认识它的具体类型。
  ///
  /// 单列一类而不是当普通文字，是因为「未知元素」与「用户真的打了一串
  /// 尖括号」在排障时是完全不同的两件事，前者需要被看见。
  unknownElement,
}

/// 一小段可渲染的正文。
@immutable
class MessageSegment {
  const MessageSegment({
    required this.kind,
    required this.text,
    this.token,
    this.resolved = true,
  });

  /// 元素类型。
  final MessageSegmentKind kind;

  /// 直接渲染出来的文本。
  final String text;

  /// 原始标识：`@` 的 openid、表情的 id、指令的参数文本。
  ///
  /// 保留它是为了排障——例如「明明 @ 了人却显示占位」时，
  /// 需要知道正文里的 openid 与事件 `mentions` 里的对不上。
  final String? token;

  /// 是否解析成功。目前只有 [MessageSegmentKind.mention] 会用到：
  /// `false` 表示正文里的 openid 没能在事件的 `mentions` 里找到昵称。
  final bool resolved;

  /// 是否为纯文本。
  bool get isText => kind == MessageSegmentKind.text;

  @override
  String toString() => 'MessageSegment($kind, "$text")';
}

/// 消息正文解析器。
///
/// 只在**认出已知格式**时才切分：普通文字里的尖括号（例如用户自己打的
/// `<abc>`）必须原样保留，否则会出现「用户的文本被吞掉」这种更糟的问题。
/// 因此除 `qqbot-` 前缀的标签外，其余 `<...>` 一律当普通文字。
abstract final class MessageContentParser {
  /// `@某人`（新格式）。
  static final RegExp _atUserNew = RegExp(
    r'<qqbot-at-user\s+id="([^"]*)"\s*/?>',
    caseSensitive: false,
  );

  /// `@某人`（旧格式，官方标注「即将弃用」但仍在流通）。
  ///
  /// `!` 容错：Discord 系客户端会写成 `<@!id>`，QQ 侧未见此写法，
  /// 但多认一种不会造成误判（正文里出现 `<@...>` 本身就只可能是这个用途）。
  static final RegExp _atUserLegacy = RegExp(r'<@!?([^<>\s]{1,64})>');

  /// `@全部成员`。
  static final RegExp _atEveryone =
      RegExp(r'<qqbot-at-everyone\s*/?>', caseSensitive: false);

  /// 指令（回车 / 参数两种）。
  static final RegExp _command = RegExp(
    r'<qqbot-cmd-(enter|input)\s+([^>]*?)/?>',
    caseSensitive: false,
  );

  /// 子频道引用。
  static final RegExp _channel = RegExp(r'<#([^<>\s]{1,64})>');

  /// 表情（频道体系）。
  static final RegExp _emoji =
      RegExp(r'<emoji:([^<>\s]{1,64})>', caseSensitive: false);

  /// 未文档化的表情标签。
  ///
  /// 真机样本：`<faceType=6,faceId="0",ext="eyJ0ZXh0IjoiIn0=">`。
  /// 字段顺序与个数都不保证，因此只匹配到第一个 `>` 为止，
  /// 具体字段交给 [_faceToken] 逐个抠——写成「精确匹配整段」的话，
  /// 官方哪天多给一个字段就会静默失配。
  static final RegExp _face = RegExp(r'<faceType=[^>]*>', caseSensitive: false);

  /// 剩余的 `qqbot-*` 自闭合标签。
  static final RegExp _unknownQqbotTag =
      RegExp(r'<qqbot-[a-z0-9-]+[^>]*/?>', caseSensitive: false);

  /// 上面所有已知模式的合并，用于一次遍历。
  static final RegExp _anyTag = RegExp(
    [
      _atUserNew.pattern,
      _atUserLegacy.pattern,
      _atEveryone.pattern,
      _command.pattern,
      _channel.pattern,
      _emoji.pattern,
      _face.pattern,
      _unknownQqbotTag.pattern,
    ].join('|'),
    caseSensitive: false,
  );

  /// 把正文切成可渲染的片段。
  ///
  /// [mentions] 是 `openid → 昵称` 的索引，来自事件的 `mentions` 字段。
  /// 官方**没有说明**正文里的占位符与 `mentions` 元素如何对应，
  /// 因此这里按「正文里的 id 命中该用户的任一标识」来匹配，
  /// 匹配不上就退化为通用占位而不是显示 openid。
  static List<MessageSegment> parse(
    String? content, {
    Map<String, String> mentions = const {},
  }) {
    final text = content ?? '';
    if (text.isEmpty) return const [];

    // 小写化的索引：正文里的十六进制 id 大小写不保证一致，
    // 而 openid 本身就是不区分大小写的标识。
    final index = <String, String>{};
    mentions.forEach((id, name) {
      final key = id.trim().toLowerCase();
      if (key.isNotEmpty && name.trim().isNotEmpty) index[key] = name.trim();
    });

    final segments = <MessageSegment>[];
    final buffer = StringBuffer();
    var cursor = 0;

    void flushText() {
      if (buffer.isEmpty) return;
      segments.add(MessageSegment(
        kind: MessageSegmentKind.text,
        text: buffer.toString(),
      ));
      buffer.clear();
    }

    for (final match in _anyTag.allMatches(text)) {
      final raw = match.group(0) ?? '';
      // 命中区域之前的部分是普通文字
      if (match.start > cursor) {
        buffer.write(text.substring(cursor, match.start));
      }
      cursor = match.end;

      final segment = _segmentFor(raw, match, index);
      if (segment == null) {
        // 认不出来就还给普通文字，绝不吞掉用户内容
        buffer.write(raw);
        continue;
      }
      flushText();
      segments.add(segment);
    }

    if (cursor < text.length) buffer.write(text.substring(cursor));
    flushText();

    return segments;
  }

  /// 把单个命中的标签转成片段；返回 `null` 表示不当作元素处理。
  static MessageSegment? _segmentFor(
    String raw,
    RegExpMatch match,
    Map<String, String> mentions,
  ) {
    final lower = raw.toLowerCase();

    if (lower.startsWith('<qqbot-at-user')) {
      final id = _firstNonEmptyGroup(match) ?? '';
      return _mention(id, mentions);
    }
    if (lower.startsWith('<qqbot-at-everyone')) {
      return const MessageSegment(
        kind: MessageSegmentKind.mentionEveryone,
        text: '@全体成员',
      );
    }
    if (lower.startsWith('<qqbot-cmd-')) {
      final attributes = _parseAttributes(_command.firstMatch(raw)?.group(2));
      final label = attributes['show'] ?? attributes['text'] ?? '';
      if (label.isEmpty) {
        return const MessageSegment(
          kind: MessageSegmentKind.unknownElement,
          text: '[指令]',
        );
      }
      return MessageSegment(
        // 前缀按需补：`text` 是「点击后发送的文本」，官方示例里本就不带 `/`，
        // 但真机上见过带 `/` 的写法，无条件再加一个会渲染成 `//xxx`。
        kind: MessageSegmentKind.command,
        text: label.startsWith('/') ? label : '/$label',
        token: attributes['text'],
      );
    }
    if (lower.startsWith('<qqbot-')) {
      // 其它 qqbot- 前缀标签：认得出是官方元素，但本项目没建模
      return const MessageSegment(
        kind: MessageSegmentKind.unknownElement,
        text: '[元素]',
      );
    }
    if (lower.startsWith('<face')) {
      return MessageSegment(
        kind: MessageSegmentKind.face,
        text: '[表情]',
        token: _faceToken(raw),
      );
    }
    if (lower.startsWith('<emoji:')) {
      return MessageSegment(
        kind: MessageSegmentKind.face,
        text: '[表情]',
        token: raw.substring('<emoji:'.length, raw.length - 1),
      );
    }
    if (lower.startsWith('<#')) {
      final id = raw.substring(2, raw.length - 1);
      return MessageSegment(
        kind: MessageSegmentKind.channel,
        text: '#${_shortId(id)}',
        token: id,
      );
    }
    if (lower.startsWith('<@')) {
      // 旧格式走这里；用第一个捕获组拿 id
      final id = _legacyMentionId(match) ?? '';
      return _mention(id, mentions);
    }
    return null;
  }

  /// `@某人` 片段。
  static MessageSegment _mention(String id, Map<String, String> mentions) {
    final token = id.trim();
    final name = mentions[token.toLowerCase()];
    if (name != null && name.isNotEmpty) {
      return MessageSegment(
        kind: MessageSegmentKind.mention,
        text: '@$name',
        token: token,
        resolved: true,
      );
    }
    return MessageSegment(
      kind: MessageSegmentKind.mention,
      text: '@某人',
      token: token,
      resolved: false,
    );
  }

  /// 取合并正则里第一个有值的捕获组。
  ///
  /// 多个模式拼成一个正则后组号会整体偏移，逐个硬编码成常量很容易在
  /// 后续增删模式时改错。这里改成「谁命中取谁」：不在匹配分支上的
  /// 捕获组一定是 `null`，所以第一个非空组就是当前模式的那个 id。
  static String? _firstNonEmptyGroup(RegExpMatch match) {
    for (var i = 1; i <= match.groupCount; i++) {
      final value = match.group(i);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// 从 `faceType` 标签里抠出可读的标识。
  ///
  /// 官方没有 `faceId → 表情图片` 的映射表，所以这里只提取出来放进 token
  /// 供排障用，界面上渲染的是中性标签而不是去猜图片地址。
  static String? _faceToken(String raw) {
    final type = RegExp(r'faceType=([^,>\s]+)', caseSensitive: false)
        .firstMatch(raw)
        ?.group(1);
    final id = RegExp(r'faceId="?([^",>\s]*)"?', caseSensitive: false)
        .firstMatch(raw)
        ?.group(1);
    final parts = [
      if (type != null && type.isNotEmpty) 'type=$type',
      if (id != null && id.isNotEmpty) 'id=$id',
    ];
    return parts.isEmpty ? null : parts.join(',');
  }

  /// 旧格式 `<@id>` 的 id。
  static String? _legacyMentionId(RegExpMatch match) {
    // 旧格式没有引号包裹，直接用整段掐头去尾，避开组号偏移的问题。
    final raw = match.group(0) ?? '';
    if (raw.length < 3) return null;
    var inner = raw.substring(2, raw.length - 1);
    if (inner.startsWith('!')) inner = inner.substring(1);
    return inner;
  }

  /// 解析标签属性（`text="x" show="y"` 这类）。
  static Map<String, String> _parseAttributes(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    final result = <String, String>{};
    for (final match
        in RegExp(r'([a-zA-Z_-]+)="([^"]*)"').allMatches(raw)) {
      result[match.group(1)!.toLowerCase()] = match.group(2)!;
    }
    return result;
  }

  /// 长 id 只露尾部，避免正文里再出现一串十六进制。
  static String _shortId(String id) {
    if (id.length <= 8) return id;
    return '…${id.substring(id.length - 6)}';
  }
}
