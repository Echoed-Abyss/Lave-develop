import 'package:flutter/foundation.dart';

import '../../core/constants/qq_limits.dart';
import '../../domain/models/qq_enums.dart';

/// 发消息请求实体（单聊与群聊共用同一套字段结构）。
///
/// 字段逐字对照官方文档（知识库 7.1 节）。官方请求体是**平铺字段**，
/// 不存在「content 内再嵌一套 JSON」的复合结构——这一点在知识库第 11 章
/// 已明确标注为「官方文档未提供」，因此不要按其他平台的经验构造。
///
/// 本类用工厂构造限制合法组合，并提供 [validate] 做发送前本地校验，
/// 目的是把「本来可以让服务端返回的 22006（消息类型与内容不匹配）」
/// 提前在客户端拦掉——用户看到的应该是明确的表单错误，而不是一次失败的请求。
@immutable
class SendMessageRequest {
  const SendMessageRequest({
    this.msgType,
    this.content,
    this.markdown,
    this.media,
    this.keyboard,
    this.msgId,
    this.eventId,
    this.msgSeq,
    this.messageReference,
    this.isWakeup,
    this.inputNotify,
  });

  /// 纯文本消息（`msg_type = 0`）。
  factory SendMessageRequest.text(
    String content, {
    String? msgId,
    String? eventId,
    int? msgSeq,
    bool? isWakeup,
    MessageReference? messageReference,
  }) =>
      SendMessageRequest(
        msgType: QqSendMsgType.text.value,
        content: content,
        msgId: msgId,
        eventId: eventId,
        msgSeq: msgSeq,
        isWakeup: isWakeup,
        messageReference: messageReference,
      );

  /// Markdown 消息（`msg_type = 2`）。
  ///
  /// 官方硬约束：**传了 markdown 后 `content` 与 `ark` 必须全为空**。
  factory SendMessageRequest.markdown(
    MessageMarkdown markdown, {
    Keyboard? keyboard,
    String? msgId,
    String? eventId,
    int? msgSeq,
    bool? isWakeup,
    MessageReference? messageReference,
  }) =>
      SendMessageRequest(
        msgType: QqSendMsgType.markdown.value,
        markdown: markdown,
        keyboard: keyboard,
        msgId: msgId,
        eventId: eventId,
        msgSeq: msgSeq,
        isWakeup: isWakeup,
        messageReference: messageReference,
      );

  /// 富媒体消息（`msg_type = 7`）。`fileInfo` 来自对应的上传接口返回值。
  factory SendMessageRequest.media(
    String fileInfo, {
    Keyboard? keyboard,
    String? msgId,
    String? eventId,
    int? msgSeq,
    bool? isWakeup,
    MessageReference? messageReference,
  }) =>
      SendMessageRequest(
        msgType: QqSendMsgType.media.value,
        media: MediaInfo(fileInfo: fileInfo),
        keyboard: keyboard,
        msgId: msgId,
        eventId: eventId,
        msgSeq: msgSeq,
        isWakeup: isWakeup,
        messageReference: messageReference,
      );

  /// 输入中状态（`msg_type = 6`，仅单聊可用）。
  ///
  /// 官方：`input_second` 为状态持续时间，**最长 60 秒**。
  factory SendMessageRequest.inputNotify({
    int second = 60,
    String? msgId,
    String? eventId,
  }) =>
      SendMessageRequest(
        msgType: QqSendMsgType.inputNotify.value,
        inputNotify: InputNotify(
          inputType: 1,
          inputSecond: second.clamp(1, 60),
        ),
        msgId: msgId,
        eventId: eventId,
      );

  /// 消息类型，决定哪个内容字段生效：0 / 2 / 6 / 7。
  final int? msgType;

  /// 文本内容。`msg_type = 0` 时为全文。
  final String? content;

  /// Markdown 消息。`msg_type = 2` 时必填。
  final MessageMarkdown? markdown;

  /// 富媒体消息。`msg_type = 7` 时填写。
  final MediaInfo? media;

  /// 内嵌键盘（按钮）。
  final Keyboard? keyboard;

  /// 被动回复的消息 ID，取自消息事件的 `d.id`。
  final String? msgId;

  /// 被动回复的事件 ID，取自**事件最外层** payload 的 `id`。
  final String? eventId;

  /// 回复消息的序号。官方：不填默认是 1；
  /// **相同的 `msg_id + msg_seq` 重复发送会失败**，递增它可对同一消息多次回复。
  final int? msgSeq;

  /// 引用回复。
  final MessageReference? messageReference;

  /// 是否为互动召回消息。官方：与 `msg_id`、`event_id` **互斥使用**。
  final bool? isWakeup;

  /// 输入中状态。
  final InputNotify? inputNotify;

  /// 序列化为官方请求体。
  ///
  /// 只输出非空字段：官方对「同时传 content 与 markdown」会直接报错，
  /// 因此不能让空值以 `null` 之外的形态出现在请求里。
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    void put(String key, Object? value) {
      if (value == null) return;
      if (value is String && value.isEmpty && key != 'content') return;
      json[key] = value;
    }

    put('msg_type', msgType);
    put('content', content);
    put('markdown', markdown?.toJson());
    put('media', media?.toJson());
    put('keyboard', keyboard?.toJson());
    put('msg_id', msgId);
    put('event_id', eventId);
    put('msg_seq', msgSeq);
    put('message_reference', messageReference?.toJson());
    put('is_wakeup', isWakeup);
    put('input_notify', inputNotify?.toJson());
    return json;
  }

  /// 发送前本地校验。
  ///
  /// 返回空列表表示通过。校验项全部来自官方明确的互斥规则：
  /// 1. `msg_type` 必须已知（官方 `type/overview` 与接口页口径不一致，
  ///    已知合法值为 0/2/6/7）；
  /// 2. 传了 markdown 后不能带 content；
  /// 3. `msg_id` 与 `event_id` 二选一；
  /// 4. `is_wakeup` 与 `msg_id`/`event_id` 互斥；
  /// 5. 纯文本消息的 content 不能为空；
  /// 6. 召回消息必须有内容载体（markdown / media / content 之一）。
  List<String> validate() {
    final errors = <String>[];

    final type = QqSendMsgType.fromValue(msgType);
    if (type == null) {
      errors.add('消息类型缺失或不受支持：msg_type=$msgType（合法值 0/2/6/7）');
      return errors;
    }

    if (markdown != null && content != null && content!.isNotEmpty) {
      errors.add('传了 markdown 后 content 必须为空（官方要求二者互斥）');
    }
    if (msgId != null && eventId != null) {
      errors.add('msg_id 与 event_id 只能二选一');
    }
    if (isWakeup == true && (msgId != null || eventId != null)) {
      errors.add('互动召回消息（is_wakeup）与 msg_id / event_id 互斥');
    }

    switch (type) {
      case QqSendMsgType.text:
        if (content == null || content!.trim().isEmpty) {
          errors.add('纯文本消息的 content 不能为空');
        }
      case QqSendMsgType.markdown:
        if (markdown == null) {
          errors.add('Markdown 消息必须提供 markdown 字段');
        } else {
          errors.addAll(markdown!.validate());
        }
      case QqSendMsgType.media:
        if (media == null || media!.fileInfo == null || media!.fileInfo!.isEmpty) {
          errors.add('富媒体消息必须提供 media.file_info（来自上传接口返回值）');
        }
      case QqSendMsgType.inputNotify:
        if (inputNotify == null) {
          errors.add('输入中状态必须提供 input_notify');
        }
    }

    if (keyboard != null) {
      errors.addAll(keyboard!.validate());
    }
    return errors;
  }

  /// 是否为被动回复（携带了 msg_id 或 event_id）。
  bool get isPassiveReply => msgId != null || eventId != null;

  /// 复制并替换 `msg_seq`。
  ///
  /// 用途：官方要求「相同的 msg_id + msg_seq 重复发送会失败」，
  /// 收到 40054005（消息被去重）时递增 seq 后重发即可。
  SendMessageRequest withMsgSeq(int seq) => SendMessageRequest(
        msgType: msgType,
        content: content,
        markdown: markdown,
        media: media,
        keyboard: keyboard,
        msgId: msgId,
        eventId: eventId,
        msgSeq: seq,
        messageReference: messageReference,
        isWakeup: isWakeup,
        inputNotify: inputNotify,
      );

  /// 实际生效的 `msg_seq`。官方未填时默认 1。
  int get effectiveMsgSeq => msgSeq ?? 1;
}

/// 官方 `MessageMarkdown`。
///
/// 官方字段说明：`template_id` 与 `custom_template_id` 均标注为**【已废弃】**，
/// 因此本项目只使用原生 `content`。
@immutable
class MessageMarkdown {
  const MessageMarkdown({this.content, this.forceVerifyImageResource});

  /// Markdown 内容。
  final String? content;

  /// 是否校验图片转存结果。为 `true` 时若图片转存失败会返回错误且消息不发送。
  final bool? forceVerifyImageResource;

  Map<String, dynamic> toJson() => {
        if (content != null) 'content': content,
        if (forceVerifyImageResource != null)
          'force_verify_image_resource': forceVerifyImageResource,
      };

  /// 本地校验。官方对 markdown 的报错码较多（40034008~40034011、40034124），
  /// 这里只拦最明显的两类：空内容与含换行的「模板参数」场景。
  List<String> validate() {
    final errors = <String>[];
    if (content == null || content!.trim().isEmpty) {
      errors.add('Markdown 内容不能为空');
    }
    return errors;
  }
}

/// 官方 `MediaInfo`。
@immutable
class MediaInfo {
  const MediaInfo({this.fileInfo});

  /// 文件数据，来自文件上传接口返回值。
  ///
  /// 官方明确：内部为序列化的二进制数据，开发者无需解析，**直接透传即可**。
  final String? fileInfo;

  Map<String, dynamic> toJson() => {
        if (fileInfo != null) 'file_info': fileInfo,
      };
}

/// 官方 `MessageReference` —— 引用回复。
@immutable
class MessageReference {
  const MessageReference({this.messageId});

  /// 被引用消息 ID，形如 `REFIDX_xxxxxx`。
  ///
  /// 官方给出两条取值路径：
  /// - 非机器人发的消息：从消息事件的 `MessageScene.ext` 的 `msg_idx` 取；
  /// - 机器人自己发的消息：从发消息请求响应的 `ext_info.ref_idx` 取。
  final String? messageId;

  Map<String, dynamic> toJson() => {
        if (messageId != null) 'message_id': messageId,
      };
}

/// 官方 `InputNotify` —— 输入中状态。
@immutable
class InputNotify {
  const InputNotify({this.inputType = 1, this.inputSecond});

  /// 官方：填 1。
  final int inputType;

  /// 状态持续时间，官方最长 60 秒。
  final int? inputSecond;

  Map<String, dynamic> toJson() => {
        'input_type': inputType,
        if (inputSecond != null) 'input_second': inputSecond,
      };
}

/// 官方 `Keyboard` —— 内嵌键盘。
@immutable
class Keyboard {
  const Keyboard({this.id, this.content});

  /// 内嵌键盘模板 ID（使用平台预设模板时填写）。
  final String? id;

  /// 自定义键盘布局。与 `id` 互斥。
  final KeyboardContent? content;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (content != null) 'content': content!.toJson(),
      };

  /// 本地校验。
  ///
  /// 官方限制：按钮最多 **5 行、每行最多 5 个**（知识库 9.1 节），
  /// 按钮文字最多 10 字符。超限会被服务端以 40034029 拒绝，
  /// 在客户端拦住可以让用户直接看到「哪一行多了」。
  List<String> validate() {
    final errors = <String>[];
    if (id == null && content == null) {
      errors.add('键盘必须提供 id 或自定义 content 之一');
    }
    if (id != null && content != null) {
      errors.add('键盘的 id 与自定义 content 互斥');
    }
    final rows = content?.rows;
    if (rows == null) return errors;

    if (rows.length > QqLimits.keyboardMaxRows) {
      errors.add('键盘最多 ${QqLimits.keyboardMaxRows} 行，当前 ${rows.length} 行');
    }
    for (var i = 0; i < rows.length; i++) {
      final buttons = rows[i].buttons;
      if (buttons.length > QqLimits.keyboardMaxButtonsPerRow) {
        errors.add(
          '第 ${i + 1} 行按钮最多 ${QqLimits.keyboardMaxButtonsPerRow} 个，'
          '当前 ${buttons.length} 个',
        );
      }
      for (final button in buttons) {
        final label = button.renderData?.label;
        if (label != null && label.runes.length > QqLimits.buttonLabelMaxChars) {
          errors.add(
            '按钮文字最多 ${QqLimits.buttonLabelMaxChars} 个字符：$label',
          );
        }
      }
    }
    return errors;
  }
}

/// 官方 `KeyboardContent`。
@immutable
class KeyboardContent {
  const KeyboardContent({this.rows = const []});

  /// 按钮行列表。
  final List<KeyboardRow> rows;

  Map<String, dynamic> toJson() => {
        'rows': rows.map((e) => e.toJson()).toList(growable: false),
      };
}

/// 官方 `Row`。
@immutable
class KeyboardRow {
  const KeyboardRow({this.buttons = const []});

  /// 行内按钮，从左到右排列。
  final List<KeyboardButton> buttons;

  Map<String, dynamic> toJson() => {
        'buttons': buttons.map((e) => e.toJson()).toList(growable: false),
      };
}

/// 官方 `Button`。
@immutable
class KeyboardButton {
  const KeyboardButton({
    this.id,
    this.renderData,
    this.action,
    this.groupId,
  });

  /// 按钮 ID，同一键盘内唯一。
  final String? id;

  /// 按钮渲染。
  final RenderData? renderData;

  /// 按钮点击行为。
  final Action? action;

  /// 分组 ID。官方：同一分组内有一个按钮操作后，其它按钮变灰不可点击，
  /// **仅当 `action.type = 1` 时有效**。
  final String? groupId;

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        if (renderData != null) 'render_data': renderData!.toJson(),
        if (action != null) 'action': action!.toJson(),
        if (groupId != null) 'group_id': groupId,
      };
}

/// 官方 `RenderData`。
@immutable
class RenderData {
  const RenderData({this.label, this.visitedLabel, this.style});

  /// 按钮文字，官方最多 10 字符。
  final String? label;

  /// 点击后文字，不传则保持不变。
  final String? visitedLabel;

  /// 样式：0 灰色线框 / 1 蓝色线框 / 3 白底红字 / 4 蓝底白字。
  final int? style;

  Map<String, dynamic> toJson() => {
        if (label != null) 'label': label,
        if (visitedLabel != null) 'visited_label': visitedLabel,
        if (style != null) 'style': style,
      };
}

/// 官方 `Action`。
@immutable
class Action {
  const Action({
    this.type,
    this.permission,
    this.data,
    this.unsupportTips,
    this.enter,
    this.reply,
    this.anchor,
    this.modal,
  });

  /// 行为类型：0 跳转按钮（http 或小程序）/ 1 回调按钮 / 2 指令按钮。
  ///
  /// 注意：官方字段 `click_limit` 与 `at_bot_show_channel_list` 已标注【已废弃】，
  /// 因此本类不再提供这两个字段。
  final int? type;

  /// 操作权限。
  final Permission? permission;

  /// 回调数据。官方：`type = 1/2` 时必填。
  final String? data;

  /// 版本过低时提示文案。
  final String? unsupportTips;

  /// 指令按钮专用：点击后直接自动发送 `data`。**仅单聊可用**，默认 false。
  final bool? enter;

  /// 指令按钮专用：指令是否带引用回复本消息，默认 false。
  final bool? reply;

  /// 指令按钮专用：置 1 时点击按钮自动唤起手Q选图器。
  /// 官方：**仅支持手机端版本 8983+ 的单聊场景，桌面端不支持**。
  final int? anchor;

  /// 用户点击二次确认操作。
  final Modal? modal;

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (permission != null) 'permission': permission!.toJson(),
        if (data != null) 'data': data,
        if (unsupportTips != null) 'unsupport_tips': unsupportTips,
        if (enter != null) 'enter': enter,
        if (reply != null) 'reply': reply,
        if (anchor != null) 'anchor': anchor,
        if (modal != null) 'modal': modal!.toJson(),
      };

  /// 是否为回调按钮（需要服务端回应）。
  bool get isCallback => type == 1;

  /// 是否为指令按钮。
  bool get isCommand => type == 2;
}

/// 官方 `Permission`。
@immutable
class Permission {
  const Permission({this.type, this.specifyUserIds, this.specifyRoleIds});

  /// 0 = 指定用户，1 = 管理员，2 = 所有人。
  final int? type;

  /// 有权限的用户 ID 列表。
  final List<String>? specifyUserIds;

  /// 有权限的身份组 ID 列表（**仅频道可用**）。
  final List<String>? specifyRoleIds;

  Map<String, dynamic> toJson() => {
        if (type != null) 'type': type,
        if (specifyUserIds != null) 'specify_user_ids': specifyUserIds,
        if (specifyRoleIds != null) 'specify_role_ids': specifyRoleIds,
      };
}

/// 官方 `Modal` —— 二次确认。
@immutable
class Modal {
  const Modal({this.content, this.confirmText, this.cancelText});

  /// 提示文本。官方：最多 40 个字符，**不能有 URL**。
  final String? content;

  /// 确认按钮文字。官方：最多 4 个字符，默认「确认」。
  final String? confirmText;

  /// 取消按钮文字。官方：最多 4 个字符，默认「取消」。
  final String? cancelText;

  Map<String, dynamic> toJson() => {
        if (content != null) 'content': content,
        if (confirmText != null) 'confirm_text': confirmText,
        if (cancelText != null) 'cancel_text': cancelText,
      };

  /// 本地校验（字数上限来自官方字段说明）。
  List<String> validate() {
    final errors = <String>[];
    final text = content;
    if (text != null) {
      if (text.runes.length > QqLimits.modalContentMaxChars) {
        errors.add('二次确认提示最多 ${QqLimits.modalContentMaxChars} 个字符');
      }
      if (text.contains('http://') || text.contains('https://')) {
        errors.add('二次确认提示不能包含 URL（官方限制）');
      }
    }
    for (final entry in {
      '确认按钮文字': confirmText,
      '取消按钮文字': cancelText,
    }.entries) {
      final value = entry.value;
      if (value != null && value.runes.length > QqLimits.modalButtonTextMaxChars) {
        errors.add('${entry.key}最多 ${QqLimits.modalButtonTextMaxChars} 个字符');
      }
    }
    return errors;
  }
}
