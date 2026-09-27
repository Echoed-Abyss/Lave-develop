import 'package:flutter/foundation.dart';

import '../../../core/utils/qq_json.dart';

/// 官方 `User` 对象。
///
/// 字段逐字对照官方文档（C2C_MESSAGE_CREATE / GROUP_AT_MESSAGE_CREATE 的
/// 「User」子表），见 `docs/qq-bot/knowledge-base.html` 5.1 节。
///
/// **为什么保留全部 8 个字段而不做归一**：官方同时存在四套用户标识——
/// `id`（OpenID 格式的唯一标识）、`union_openid`（跨应用统一 OpenID）、
/// `user_openid`（单聊场景）、`member_openid`（群聊场景）。它们的适用范围与
/// 生成规则都不同，且官方明确标注部分字段「可能为空」。
/// 归一动作放在领域层（`ActorRef`）做，协议层必须原样保留，
/// 否则一旦需要回调官方接口就会缺少必要的标识。
@immutable
class QqUser {
  const QqUser({
    this.id,
    this.username,
    this.avatar,
    this.bot,
    this.unionOpenid,
    this.unionUserAccount,
    this.userOpenid,
    this.memberOpenid,
    this.memberRole,
  });

  /// 用户唯一标识（OpenID 格式）。
  final String? id;

  /// 用户昵称。
  final String? username;

  /// 头像 URL。
  ///
  /// ⚠️ 官方对**单聊 / 群聊**的 User 子表（`C2C_MESSAGE_CREATE`、
  /// `GROUP_AT_MESSAGE_CREATE`）**并未定义该字段**；它只出现在频道（Guild）
  /// 体系的事件里（`AT_MESSAGE_CREATE` / `MESSAGE_CREATE` / `DIRECT_MESSAGE_CREATE`），
  /// 以及 `GET /users/@me` 的响应中。
  ///
  /// 这里仍然解析它，理由是「有就用、没有就退回占位」比「假设永远没有」更稳：
  /// 官方一旦在消息事件里补上该字段，本项目无需改动即可显示真实头像。
  final String? avatar;

  /// 是否为机器人。
  final bool? bot;

  /// 跨应用统一用户 OpenID（官方标注可能为空）。
  final String? unionOpenid;

  /// 跨应用统一用户账号（官方标注可能为空）。
  final String? unionUserAccount;

  /// 用户 OpenID —— **单聊场景使用**，作为单聊发消息接口的路径参数。
  final String? userOpenid;

  /// 群成员 OpenID —— **群聊场景使用**。
  final String? memberOpenid;

  /// 群内角色：`member` / `admin` / `owner`（官方枚举原样保留为字符串）。
  final String? memberRole;

  factory QqUser.fromJson(Map<String, dynamic> json) => QqUser(
        id: QqJson.str(json['id']),
        username: QqJson.str(json['username']),
        avatar: _nonEmpty(json['avatar']),
        bot: QqJson.boolean(json['bot']),
        unionOpenid: QqJson.str(json['union_openid']),
        unionUserAccount: QqJson.str(json['union_user_account']),
        userOpenid: QqJson.str(json['user_openid']),
        memberOpenid: QqJson.str(json['member_openid']),
        memberRole: QqJson.str(json['member_role']),
      );

  /// 头像地址：空串与缺失**都归一为 `null`**。
  ///
  /// `QqJson.str` 刻意保留空串（`union_openid` 这类字段空串是有意义的），
  /// 但头像不同：空串与「官方没给这个字段」对界面是同一件事——没有头像。
  /// 统一成 `null` 后，下游只需要判断一种情况。
  static String? _nonEmpty(Object? raw) {
    final text = QqJson.str(raw);
    if (text == null || text.trim().isEmpty) return null;
    return text;
  }

  /// 单聊场景的会话标识：优先 `user_openid`，回退到 `id`。
  ///
  /// 存在回退的原因：官方示例中部分事件只给了 `id`（形如
  /// `ROBOT1.0_...` 之外的用户标识），若严格要求 `user_openid`
  /// 会导致这类事件无法定位会话。
  String? get c2cScopeId => userOpenid ?? id;
}
