import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../core/logging/log_service.dart';
import '../repository/bot_repository.dart';
import '../repository/history_repository.dart';

/// 极简 JSON 文档存储。
///
/// 为什么不用 drift：本项目当前阶段的硬要求是「能编译、能跑」，
/// 而 drift 需要 `build_runner` 代码生成，多一层构建步骤就多一类
/// 「生成物过期导致编译失败」的问题。消息与日志的规模在自用场景下
/// 用单个 JSON 文件完全够用（每次写入整体重写）。
///
/// 代价（如实记录，便于后续升级）：
/// - 没有索引与 SQL 查询能力，按条件检索是内存过滤；
/// - 每次写入重写整个文件，条数上万后会变慢；
/// - 需要调用方自行限制保留条数（见各 Repository 的 maxEntries）。
///
/// 升级路径：把本类替换为 drift 实现即可，上层只依赖
/// [JsonDocStoreLike] / [BotStoreLike] / [HistoryStoreLike] 三个接口。
class JsonDocStore implements JsonDocStoreLike, BotStoreLike, HistoryStoreLike {
  JsonDocStore({required this.fileName});

  /// 文件名（落在应用文档目录下）。
  final String fileName;

  File? _cached;

  /// 解析出文件句柄（首次调用时创建目录）。
  Future<File> _resolveFile() async {
    final cached = _cached;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _cached = file;
    return file;
  }

  /// 读取一个 JSON 对象；文件不存在或内容损坏时返回空对象。
  ///
  /// **损坏时返回空而不抛异常**：本地缓存的使命是提升体验，
  /// 一旦它变成「打不开 App」的原因，就得不偿失。
  Future<Map<String, dynamic>> read() async {
    try {
      final file = await _resolveFile();
      final text = await file.readAsString();
      if (text.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      AppLogger.warn('本地文档格式异常，已忽略：$fileName', tag: 'store');
      return <String, dynamic>{};
    } catch (error, stack) {
      AppLogger.error('读取本地文档失败：$fileName',
          error: error, stackTrace: stack, tag: 'store');
      return <String, dynamic>{};
    }
  }

  /// 读取一个 JSON 数组；异常时返回空列表。
  @override
  Future<List<Map<String, dynamic>>> readList(String key) async {
    final doc = await read();
    final raw = doc[key];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// 覆盖写入。
  ///
  /// 先写临时文件再重命名：避免写入过程中被杀进程导致文件半截损坏
  /// （移动端随时可能被系统回收，这个风险是真实存在的）。
  Future<void> write(Map<String, dynamic> doc) async {
    try {
      final file = await _resolveFile();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(doc), flush: true);
      await temp.rename(file.path);
    } catch (error, stack) {
      AppLogger.error('写入本地文档失败：$fileName',
          error: error, stackTrace: stack, tag: 'store');
    }
  }

  /// 写入一个数组字段。
  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {
    final doc = await read();
    doc[key] = items;
    await write(doc);
  }

  /// 删除存储文件（用于「清除数据」）。
  Future<void> clear() async {
    try {
      final file = await _resolveFile();
      if (await file.exists()) await file.delete();
      _cached = null;
    } catch (error) {
      AppLogger.warn('清除本地文档失败：$fileName（$error）', tag: 'store');
    }
  }
}
