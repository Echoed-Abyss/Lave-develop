import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../constants/qq_limits.dart';

/// 富媒体上传所需的校验值集合。
///
/// 官方 `upload_prepare` 把 `md5` / `sha1` / `md5_10m` 三个都标为必填，
/// 用途是服务端做完整性与「同一文件是否已存在」的判断。
/// 少传不会立刻报错，但服务端就失去了比对依据：要么白跑一次转存，
/// 要么在传输出错时给出一个与真实原因无关的报错。
class MediaChecksum {
  const MediaChecksum({
    required this.md5,
    required this.sha1,
    required this.md5Prefix,
  });

  /// 整个文件的 MD5（十六进制小写）。
  final String md5;

  /// 整个文件的 SHA1（十六进制小写）。
  final String sha1;

  /// 文件前缀的 MD5，前缀长度见 [QqLimits.md5PrefixBytes]。
  final String md5Prefix;

  /// 一次算出三个校验值。
  ///
  /// `md5_10m` 取的是**文件前 [QqLimits.md5PrefixBytes] 字节**
  /// （10002432 字节，约 9.54 MB，不是常见的 10MiB）。这个数字来自官方文档
  /// 原文，不要顺手改成 `10 * 1024 * 1024`。
  ///
  /// 文件不超过取样长度时，`md5_10m` 就等于整个文件的 MD5——
  /// 这不是特例，而是「取前 N 字节」在该情况下的自然结果。
  factory MediaChecksum.of(Uint8List bytes) {
    final prefixEnd = bytes.length < QqLimits.md5PrefixBytes
        ? bytes.length
        : QqLimits.md5PrefixBytes;
    return MediaChecksum(
      md5: md5Of(bytes),
      sha1: sha1Of(bytes),
      md5Prefix: md5Of(Uint8List.sublistView(bytes, 0, prefixEnd)),
    );
  }

  /// 单块数据的 MD5。分片上传的 `upload_part_finish` 要传的就是它。
  static String md5Of(List<int> bytes) => crypto.md5.convert(bytes).toString();

  /// 单块数据的 SHA1。当前只在整文件校验时用到。
  static String sha1Of(List<int> bytes) => crypto.sha1.convert(bytes).toString();

  /// 只暴露前 8 位，避免日志里刷出一整串摘要。
  @override
  String toString() =>
      'MediaChecksum(md5=${md5.substring(0, 8)}…, sha1=${sha1.substring(0, 8)}…)';
}
