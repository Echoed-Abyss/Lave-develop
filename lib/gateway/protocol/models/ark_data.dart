import 'package:flutter/foundation.dart';

import '../../../core/utils/qq_json.dart';

/// 官方 `ARKData` —— 结构化卡片消息数据。
///
/// 仅在事件的 `message_type = 3` 时有值（知识库 5.1 节）。
///
/// 三个字段的分工：
/// - `ark_type`：机器可判定的类型标识（用于选择渲染方式）；
/// - `ark_name`：中文类型名（用于界面标题）；
/// - `fields`：**结构不固定的开放字段集**，官方只给出「常见键名」清单，
///   并未定义为固定 schema。因此这里保留为 `Map<String, dynamic>`，
///   不做强类型建模——强类型化会在官方新增键时直接丢字段。
@immutable
class ArkData {
  const ArkData({
    this.prompt,
    this.arkType,
    this.arkName,
    this.fields = const {},
  });

  /// 卡片消息中的用户操作提示文本。
  final String? prompt;

  /// 卡片消息类型标识。
  ///
  /// 官方取值：`tuwen`（图文 H5）、`feed`（图文卡片）、`miniapp`（小程序）、
  /// `map`（位置卡片）、`contact_card`（好友名片）、`video_share`（视频分享）、
  /// `music_together`（一起听歌）、`picture`（图片）。
  final String? arkType;

  /// 卡片消息类型的中文名称。
  final String? arkName;

  /// 卡片字段（官方只给出常见键名，非固定 schema）。
  final Map<String, dynamic> fields;

  factory ArkData.fromJson(Map<String, dynamic> json) => ArkData(
        prompt: QqJson.str(json['prompt']),
        arkType: QqJson.str(json['ark_type']),
        arkName: QqJson.str(json['ark_name']),
        fields: QqJson.map(json['fields']) ?? const {},
      );

  /// 取字符串型字段（官方常见键：`title` / `desc` / `jump_url` / `preview` /
  /// `source` / `source_logo` / `tag_icon` / `nickname` / `avatar` / `address`）。
  String? field(String key) => QqJson.str(fields[key]);

  /// 卡片标题。官方常见键含 `title`。
  String? get title => field('title');

  /// 卡片描述。
  String? get description => field('desc');

  /// 跳转链接。
  String? get jumpUrl => field('jump_url');

  /// 界面标题：优先中文类型名，回退到标题，再回退到原始类型标识。
  ///
  /// 三层回退的原因：官方对 `ark_name` 的说明是「中文名称」，
  /// 但示例里出现过该字段缺失的情况；此时用 `title` 比直接显示
  /// 英文 `ark_type` 更可读。
  String? get displayName =>
      (arkName?.isNotEmpty ?? false)
          ? arkName
          : ((title?.isNotEmpty ?? false) ? title : arkType);

  /// 是否可跳转。
  bool get hasJumpUrl => jumpUrl != null && jumpUrl!.isNotEmpty;
}
