part of 'qq_event.dart';

/// 好友相关事件。字段逐字对照官方文档（知识库 5.4 节）。

/// 官方 `FriendAuthor`。
///
/// 注意：官方对好友事件单独定义了这个对象，**只有 `union_openid` 一个字段**，
/// 与消息事件的 `User` 不是同一个结构，不要复用。
@immutable
class FriendAuthor {
  const FriendAuthor({this.unionOpenid});

  /// 用户统一 OpenID（跨应用标识）。
  final String? unionOpenid;

  factory FriendAuthor.fromJson(Map<String, dynamic> json) =>
      FriendAuthor(unionOpenid: QqJson.str(json['union_openid']));
}

/// `FRIEND_ADD` —— 用户添加机器人好友。
///
/// 官方触发时机原文：通过传 `scene_param` 中的 `callback_data`
/// 可区分不同来源的添加好友场景。
/// 官方允许用它作为被动回复的 `event_id`。
@immutable
class FriendAdd extends QqEvent {
  const FriendAdd({
    required super.eventId,
    required super.seq,
    this.timestamp,
    this.openid,
    this.scene,
    this.sceneParam,
    this.author,
    this.shortCode,
  });

  @override
  String get typeName => 'FRIEND_ADD';

  @override
  bool get isLifecycleEvent => true;

  /// 添加时间（官方标注 Unix 秒整数）。
  final DateTime? timestamp;

  /// 用户 OpenID。
  final String? openid;

  /// 加好友场景值。
  ///
  /// 官方枚举：1000=缺省默认，1001=网络搜索（全部 tab），
  /// 1002=网络搜索（机器人 tab），1003=群场景，1004=空间场景，
  /// 2001=站内分享资料页，2002=站外分享资料页，
  /// 2003=开发者生成的分享链接（站内），2004=开发者生成的分享链接（站外）。
  final int? scene;

  /// 开发者自定义的回调数据（`callback_data`），用于区分不同来源。
  final String? sceneParam;

  /// 用户信息。
  final FriendAuthor? author;

  /// 机器人分享链接的短链 code。
  final String? shortCode;

  factory FriendAdd.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      FriendAdd(
        eventId: eventId,
        seq: seq,
        timestamp: QqTime.tryParse(json['timestamp']),
        openid: QqJson.str(json['openid']),
        scene: QqJson.integer(json['scene']),
        sceneParam: QqJson.str(json['scene_param']),
        author: json['author'] == null
            ? null
            : FriendAuthor.fromJson(QqJson.map(json['author'])!),
        shortCode: QqJson.str(json['short_code']),
      );

  /// 是否来自开发者生成的分享链接（站内 2003 / 站外 2004）。
  bool get isFromDeveloperShareLink => scene == 2003 || scene == 2004;

  /// 是否有自定义来源标识。官方建议用它区分不同来源，
  /// 因此界面与日志应优先展示 `scene_param`。
  bool get hasSceneParam => sceneParam != null && sceneParam!.isNotEmpty;
}

/// `FRIEND_DEL` —— 用户删除机器人好友。
@immutable
class FriendDel extends QqEvent {
  const FriendDel({
    required super.eventId,
    required super.seq,
    this.timestamp,
    this.openid,
    this.author,
  });

  @override
  String get typeName => 'FRIEND_DEL';

  @override
  bool get isLifecycleEvent => true;

  /// 删除时间（官方标注 Unix 秒整数）。
  final DateTime? timestamp;

  /// 用户 OpenID。
  final String? openid;

  /// 用户信息。
  final FriendAuthor? author;

  factory FriendDel.fromJson(
    Map<String, dynamic> json,
    String? eventId,
    int? seq,
  ) =>
      FriendDel(
        eventId: eventId,
        seq: seq,
        timestamp: QqTime.tryParse(json['timestamp']),
        openid: QqJson.str(json['openid']),
        author: json['author'] == null
            ? null
            : FriendAuthor.fromJson(QqJson.map(json['author'])!),
      );
}
