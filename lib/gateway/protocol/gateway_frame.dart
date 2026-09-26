import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';
import 'models/qq_user.dart';
import 'qq_opcode.dart';

/// WSS 通用载荷与连接期报文模型。
///
/// 逐字对照官方文档（知识库 3.3 / 3.5 节）。
/// 全部解析都刻意「宽松」：官方示例本身存在字段缺失与类型不一致
/// （例如通用 payload 的 `id` 有时有、有时没有；READY 的 `d` 官方只给示例、
/// 未给字段表），因此这里一律允许为空，绝不因为一个字段缺失就让整帧解析失败。

/// 网关下行/上行的通用载荷结构。
///
/// 官方原文：`payload` 指的是在 webhook 或 websocket 连接上传输的数据，
/// 网关的上下行消息采用的都是同一个结构。
@immutable
class GatewayFrame {
  const GatewayFrame({
    this.id,
    this.op,
    this.rawOp,
    this.seq,
    this.type,
    this.data,
  });

  /// 事件 id。
  ///
  /// 官方两处示例不一致：一份含 `"id":"event_id"`，另一份没有该字段。
  /// 因此声明为可空，且**被动回复取 event_id 时要用外层这个 id**
  /// （与消息事件的 `d.id` 不是同一个东西）。
  final String? id;

  /// 解析后的 opcode。未知 op 时为 `null`。
  final QqOpCode? op;

  /// 原始 op 数值。即使 [op] 为 `null` 也保留，便于排查官方新增的 op。
  final int? rawOp;

  /// 下行消息序列号（`s`）。
  ///
  /// 两个用途：心跳报文的 `d`，以及 Resume 的 `seq`。
  final int? seq;

  /// 事件类型（`t`）。仅 `op = 0`（Dispatch）时有意义。
  final String? type;

  /// 事件内容（`d`）。保持为 `Object?`，因为不同事件的 `d` 结构完全不同，
  /// 由事件解码层按 `t` 分派后再做具体解析。
  final Object? data;

  factory GatewayFrame.fromJson(Map<String, dynamic> json) {
    final rawOp = QqJson.integer(json['op']);
    return GatewayFrame(
      id: QqJson.str(json['id']),
      op: QqOpCode.fromValue(rawOp),
      rawOp: rawOp,
      seq: QqJson.integer(json['s']),
      type: QqJson.str(json['t']),
      data: json['d'],
    );
  }

  /// 是否为服务端推送事件帧。
  bool get isDispatch => op == QqOpCode.dispatch;

  /// 是否为未知 opcode 的帧（官方未定义 3/4/5/8）。
  bool get isUnknownOp => op == null;
}

/// OpCode 10 Hello 的载荷。
///
/// 官方原文：一旦连接成功，就会返回 OpCode 10 Hello 消息，
/// 这个消息主要的内容是心跳周期，单位毫秒（milliseconds）。
@immutable
class HelloData {
  const HelloData({required this.heartbeatIntervalMs});

  /// 心跳周期（毫秒）。官方示例值 45000。
  ///
  /// **必须使用服务端下发的值，不得硬编码**——官方未承诺该值固定。
  final int heartbeatIntervalMs;

  /// 心跳周期（Duration）。
  Duration get heartbeatInterval => Duration(milliseconds: heartbeatIntervalMs);

  factory HelloData.fromJson(Map<String, dynamic> json) => HelloData(
        // 缺失时按官方示例值兜底：Hello 缺心跳周期意味着无法正常保活，
        // 与其让上层拿到 0 而疯狂发包触发 4008，不如用官方示例值。
        heartbeatIntervalMs: QqJson.integer(json['heartbeat_interval']) ?? 45000,
      );
}

/// OpCode 2 Identify 的载荷。
///
/// 逐字对照官方 `d` 字段表（知识库 3.5 节）。
@immutable
class IdentifyPayload {
  const IdentifyPayload({
    required this.token,
    required this.intents,
    this.shard = const [0, 1],
    this.properties = const {},
  });

  /// 鉴权 token。
  ///
  /// **官方存在口径冲突**：字段表写 `格式为 "QQBot {AccessToken}"`，
  /// 而另一页正文写 `格式为 Bot {appid}.{app_token}`，官方未指明以哪个为准。
  /// 因此本字段只要求「拼好的完整字符串」，具体拼法由凭证层决定
  /// （见 `docs/qq-bot/app-architecture.html` 第 9 章待实测清单第 1 项）。
  final String token;

  /// 本次连接要接收的事件（intents 掩码）。见 [QqIntents]。
  final int intents;

  /// 分片参数，两个元素的数组。
  ///
  /// 官方明确：若无需分片，使用 `[0, 1]` 即可。移动端单机场景不做分片。
  final List<int> shard;

  /// 官方原文：目前无实际作用，可以按照自己的实际情况填写，也可以留空。
  ///
  /// 尽管官方说「无实际作用」，本项目仍传入真实平台信息：
  /// 若平台后续按客户端特征做风控，填真实值比留空更安全
  /// （属于知识库第 11 章「官方未提供」项的保守选择）。
  final Map<String, String> properties;

  Map<String, dynamic> toJson() => {
        'token': token,
        'intents': intents,
        'shard': shard,
        'properties': properties,
      };

  /// 构造符合官方示例形态的 `properties`。
  ///
  /// 官方示例字段为 `$os` / `$browser` / `$device`。
  factory IdentifyPayload.withPlatformProperties({
    required String token,
    required int intents,
    required String os,
    String browser = 'Lave',
    String device = 'Lave',
    List<int> shard = const [0, 1],
  }) =>
      IdentifyPayload(
        token: token,
        intents: intents,
        shard: shard,
        properties: {r'$os': os, r'$browser': browser, r'$device': device},
      );
}

/// OpCode 6 Resume 的载荷。
///
/// 官方只给出 JSON 结构与 `seq` 的文字说明，**未提供字段表**（知识库 3.5 节）。
@immutable
class ResumePayload {
  const ResumePayload({
    required this.token,
    required this.sessionId,
    required this.seq,
  });

  /// 鉴权 token，与 Identify 相同。
  final String token;

  /// 上一次 Identify 成功时 READY 事件下发的会话 id。
  final String sessionId;

  /// 已处理完成的最大事件序列号（即事件流的 `s`）。
  ///
  /// 官方原文：`seq` 指的是在接收事件时候的 `s` 字段，推荐开发者
  /// **在处理过事件之后**记录下 `s`，这样 resume 时 websocket 会自动补发
  /// 这个 seq 之后的事件。注意是「处理过之后」而非「收到时」。
  final int? seq;

  Map<String, dynamic> toJson() => {
        'token': token,
        'session_id': sessionId,
        'seq': seq,
      };
}

/// OpCode 1 Heartbeat 的载荷（`d` 即最后收到的 `s`）。
///
/// 官方原文：`d` 为客户端收到的最新的消息的 `s`，
/// **如果是首次连接，`d` 传 `null`**。
@immutable
class HeartbeatPayload {
  const HeartbeatPayload(this.seq);

  /// 最后收到的 `s`；首次连接为 `null`。
  final int? seq;

  /// 官方示例为裸值 `{"op":1,"d":251}`，不是对象。
  Object? toData() => seq;
}

/// Op0 `t = READY` 的载荷。
///
/// 官方只给出示例、**未提供字段表**（知识库 3.5 节），因此全部字段可空。
/// `session_id` 是 Resume 的前提，必须落盘。
@immutable
class ReadyData {
  const ReadyData({this.version, this.sessionId, this.user, this.shard});

  /// 版本号，官方示例为 1。
  final int? version;

  /// 会话 id。**Resume 的唯一凭据**。
  final String? sessionId;

  /// 机器人自身信息。
  final QqUser? user;

  /// 官方示例中 READY 的 shard 为 `[0, 0]`（注意与 Identify 请求里的
  /// `[0, 1]` 形态不同，官方未解释原因，故原样保留）。
  final List<int>? shard;

  factory ReadyData.fromJson(Map<String, dynamic> json) {
    final rawShard = json['shard'];
    return ReadyData(
      version: QqJson.integer(json['version']),
      sessionId: QqJson.str(json['session_id']),
      user: json['user'] == null ? null : QqUser.fromJson(QqJson.map(json['user'])!),
      shard: rawShard is List
          ? rawShard
              .map((e) => QqJson.integer(e))
              .whereType<int>()
              .toList(growable: false)
          : null,
    );
  }

  /// 是否为可用的 READY（必须含 session_id）。
  bool get isUsable => sessionId != null && sessionId!.isNotEmpty;
}

/// Op0 `t = RESUMED` 的载荷。
///
/// 官方示例中 `d` 为空字符串，故这里不承载任何字段，
/// 仅作为「补发已完成」的信号使用。
@immutable
class ResumedData {
  const ResumedData();

  /// 单例，避免重复创建。
  static const ResumedData instance = ResumedData();
}
