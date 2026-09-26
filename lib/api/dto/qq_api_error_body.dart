import 'package:flutter/foundation.dart';

import '../../core/utils/qq_json.dart';

/// 官方统一错误体。
///
/// 官方原文：错误码分为两部分——**http 状态码** 与 **http body 返回的
/// json 中的 `err_code`**。官方示例：
/// ```json
/// {
///   "err_code": 40034005,
///   "message": "回复消息msg_id已过期",
///   "trace_id": "4a8a61565b909f199b1ec169fdd6f49e"
/// }
/// ```
///
/// `trace_id` 也可从响应头 `X-Tps-trace-ID` 获取，两者取其一即可。
/// 它是找平台协助定位问题的唯一凭据，因此必须完整保留到日志与界面的诊断信息里。
@immutable
class QqApiErrorBody {
  const QqApiErrorBody({this.errCode, this.message, this.traceId});

  /// 官方业务错误码。
  ///
  /// 兼容两种键名：v2 接口用 `err_code`；取 access_token 接口用 `code`
  /// （见 [AccessTokenResponse]）。两者语义相同，都是「业务错误码」。
  final int? errCode;

  /// 官方错误信息。**仅用于日志与展示，不作为逻辑判据**。
  final String? message;

  /// 平台链路追踪 ID。
  final String? traceId;

  factory QqApiErrorBody.fromJson(Map<String, dynamic> json) => QqApiErrorBody(
        errCode: QqJson.integer(json['err_code']) ??
            QqJson.integer(json['code']),
        message: QqJson.str(json['message']),
        traceId: QqJson.str(json['trace_id']),
      );

  /// 是否包含任何有效信息。
  ///
  /// 用于判断「响应体是否可解析为官方错误体」：HTTP 500 之类由网关返回的
  /// 错误页通常是 HTML，解析后所有字段都为空。
  bool get isEmpty => errCode == null && message == null && traceId == null;

  /// 从响应头补齐 traceId（响应体没给时使用）。
  QqApiErrorBody withTraceIdFrom(String? headerTraceId) {
    if (traceId != null && traceId!.isNotEmpty) return this;
    return QqApiErrorBody(
      errCode: errCode,
      message: message,
      traceId: headerTraceId,
    );
  }
}
