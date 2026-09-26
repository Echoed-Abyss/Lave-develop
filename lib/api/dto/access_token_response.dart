import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';

/// `POST /app/getAppAccessToken` 的响应实体。
///
/// 官方字段（知识库 2.2 节）：
/// - 成功：`{access_token, expires_in}`；
/// - 失败：`{code, message}`。
///
/// **必须注意的官方说明**：该接口的业务错误通过响应体的 `code` 返回，
/// **即使调用失败，HTTP 返回码仍为 200**。因此绝不能只看状态码判断成功与否，
/// 也不能用 `message` 判定错误类型（官方明确其内容可能随时调整）。
@immutable
class AccessTokenResponse {
  const AccessTokenResponse({
    this.accessToken,
    this.expiresIn,
    this.code,
    this.message,
  });

  /// 获取到的凭证。
  final String? accessToken;

  /// 凭证有效时间（秒）。官方：目前是 7200 秒之内的值。
  ///
  /// 官方文档标注类型为 number，但示例里是字符串 `"7200"`，
  /// 因此统一走 [QqJson.integer] 容忍两种形态。
  final int? expiresIn;

  /// 失败时的业务错误码（如 100007 / 100016 / 10004 / 100001）。
  final int? code;

  /// 失败信息，仅用于人工排查。
  final String? message;

  factory AccessTokenResponse.fromJson(Map<String, dynamic> json) =>
      AccessTokenResponse(
        accessToken: QqJson.str(json['access_token']),
        expiresIn: QqJson.integer(json['expires_in']),
        code: QqJson.integer(json['code']),
        message: QqJson.str(json['message']),
      );

  /// 是否成功。
  ///
  /// 判定依据是「拿到了非空 token 且业务码为 0 或缺失」。
  /// 不能只判断 `code == 0`，因为成功响应里根本没有 `code` 字段。
  bool get isSuccess =>
      accessToken != null &&
      accessToken!.isNotEmpty &&
      (code == null || code == 0);

  /// 凭证有效期。
  ///
  /// 官方给出的默认值是 7200 秒；当响应未携带 `expires_in` 时按官方默认值兜底，
  /// 避免因为缺少该字段就把凭证当成「立即过期」而反复请求（会触发限流）。
  Duration get ttl => Duration(seconds: expiresIn ?? 7200);

  /// 是否已进入需要提前换新的窗口。
  ///
  /// 官方机制：在过期前 **60 秒**内再次获取会返回新的 token，
  /// 且老 token 在这 60 秒内仍然有效。因此刷新时机取「剩余时间 ≤ 60 秒」。
  bool needsRefresh(DateTime? issuedAt, {required Duration lead}) {
    if (issuedAt == null) return true;
    return DateTime.now().isAfter(issuedAt.add(ttl).subtract(lead));
  }
}
