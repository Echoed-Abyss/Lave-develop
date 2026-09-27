import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../core/logging/log_service.dart';
import '../repository/bot_repository.dart';

/// 极简 JSON 文档存储。
///
/// ## 为什么不直接用文件做「读-改-写」
///
/// 本存储被多个写入方共用：机器人账号与会话水位、消息与事件、主题与订阅设置、
/// 日志、插件启用状态。如果每次写入都「读文件 → 改一个键 → 整份写回」，
/// 两个写入方并发时就会互相覆盖——后写的一方把先写的一方刚改的键丢掉。
/// 这不是理论风险：日志的定时落盘与消息落盘是独立触发的，很容易撞上，
/// 表现为「设置偶尔自己变回去」「消息偶发丢失」，且完全无迹可查。
///
/// 因此这里改为：
/// 1. **内存中的文档是唯一真相**，首次访问时从磁盘载入一次；
/// 2. 所有修改都改内存（同步、原子）；
/// 3. 落盘经 [Future] 链**串行化**，不会两次写入交错；
/// 4. 写临时文件再重命名，避免写到一半被杀进程留下半截文件。
///
/// ## 为什么不选数据库（drift / sqflite）
///
/// 这些需要 `build_runner` 代码生成或额外的原生依赖，多一层构建步骤
/// 就多一类「生成物过期导致编译失败」的问题。自用场景的数据量（消息、
/// 日志各按千条上限）用单文件完全够。升级路径集中在三个接口后面：
/// [JsonDocStoreLike]、[BotStoreLike]、[ListStoreLike]。
class JsonDocStore implements JsonDocStoreLike, BotStoreLike, ListStoreLike {
  JsonDocStore({required this.fileName});

  /// 文件名（落在应用文档目录下）。
  final String fileName;

  File? _cachedFile;

  /// 内存中的唯一真相。`null` 表示尚未载入。
  Map<String, dynamic>? _memory;

  /// 落盘队列：保证同一时刻只有一次写入在跑。
  Future<void> _writeChain = Future<void>.value();

  Future<File> _resolveFile() async {
    final cached = _cachedFile;
    if (cached != null) return cached;
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _cachedFile = file;
    return file;
  }

  /// 取内存文档，必要时从磁盘载入。
  Future<Map<String, dynamic>> _document() async {
    final cached = _memory;
    if (cached != null) return cached;

    var loaded = <String, dynamic>{};
    try {
      final file = await _resolveFile();
      final text = await file.readAsString();
      if (text.trim().isNotEmpty) {
        final decoded = jsonDecode(text);
        if (decoded is Map) loaded = decoded.cast<String, dynamic>();
        if (decoded is! Map) {
          AppLogger.warn('本地文档格式异常，已按空文档处理：$fileName', tag: 'store');
        }
      }
    } catch (error, stack) {
      // 损坏时按空文档继续：本地缓存的使命是提升体验，
      // 一旦它变成「打不开 App」的原因就得不偿失。
      AppLogger.error('读取本地文档失败：$fileName',
          error: error, stackTrace: stack, tag: 'store');
      loaded = <String, dynamic>{};
    }
    _memory = loaded;
    return loaded;
  }

  /// 读取整份文档的**副本**。
  ///
  /// 返回副本而不是内存对象本身：调用方常常是「读出 → 改一个键 → 写回」，
  /// 若直接给内部对象，中途的修改会立刻影响其他读取方，
  /// 让本该原子的操作变成半成品可见。
  Future<Map<String, dynamic>> read() async =>
      Map<String, dynamic>.of(await _document());

  /// 读取一个 JSON 数组字段；不存在或类型不符时返回空列表。
  @override
  Future<List<Map<String, dynamic>>> readList(String key) async {
    final raw = (await _document())[key];
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  /// 合并写入若干键（不是整份替换）。
  ///
  /// 语义是「upsert 给定的键」，因为本项目所有写入方都只关心自己那几个键；
  /// 整份替换会让任何一个写入方意外抹掉别人的数据。
  Future<void> write(Map<String, dynamic> doc) async {
    (await _document()).addAll(doc);
    await _flush();
  }

  /// 写入一个数组字段。
  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {
    (await _document())[key] = items;
    await _flush();
  }

  /// 把当前内存文档串行落盘。
  Future<void> _flush() {
    final memory = _memory;
    if (memory == null) return Future<void>.value();
    // 排到链尾再执行：即使前一次写入还没结束，本次也不会与之交错。
    _writeChain = _writeChain.then((_) => _writeToDisk(memory)).catchError(
      (Object error) {
        AppLogger.warn('写入本地文档失败：$fileName（$error）', tag: 'store');
      },
    );
    return _writeChain;
  }

  Future<void> _writeToDisk(Map<String, dynamic> memory) async {
    final file = await _resolveFile();
    final temp = File('${file.path}.tmp');
    // 写临时文件再重命名：移动端随时可能被系统回收，
    // 直接写目标文件会有较大概率留下半截 JSON。
    await temp.writeAsString(jsonEncode(memory), flush: true);
    await temp.rename(file.path);
  }

  /// 删除存储文件与内存副本（用于「清除数据」）。
  Future<void> clear() async {
    try {
      _memory = <String, dynamic>{};
      final file = await _resolveFile();
      if (await file.exists()) await file.delete();
      _cachedFile = null;
      _memory = null;
    } catch (error) {
      AppLogger.warn('清除本地文档失败：$fileName（$error）', tag: 'store');
    }
  }
}

/// 「按键读写一组记录」的最小依赖面。
///
/// 放在这里而不是某个具体仓库里：消息历史、事件日志、收发统计都需要它，
/// 而它描述的是**存储能力**，不是任何一个仓库的业务。各仓库只依赖这个接口，
/// 因此换存储实现（例如将来换成带索引的本地数据库）时改动面可控。
abstract interface class ListStoreLike {
  Future<List<Map<String, dynamic>>> readList(String key);

  Future<void> writeList(String key, List<Map<String, dynamic>> items);
}
