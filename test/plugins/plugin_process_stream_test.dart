import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/domain/models/plugin_models.dart';
import 'package:lavedevelop/plugins/plugin_runtime.dart';

/// 一个假插件进程。
///
/// 只实现 [PluginProcess] 真正会用到的那几个成员（stdout / stderr / exitCode），
/// 其余交给 `noSuchMethod`——本测试不需要 stdin，也不需要真正杀进程。
class _FakeProcess implements Process {
  final StreamController<List<int>> _out = StreamController<List<int>>();
  final StreamController<List<int>> _err = StreamController<List<int>>();
  final Completer<int> _exit = Completer<int>();

  @override
  int get pid => 4242;

  @override
  Stream<List<int>> get stdout => _out.stream;

  @override
  Stream<List<int>> get stderr => _err.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(-9);
    return true;
  }

  /// 模拟插件往 stdout 写一行（走真实字节 → utf8 → 按行切分这条链路，
  /// 而不是直接塞一个对象进流，否则测不到解码与分帧）。
  void writeLine(String line) => _out.add(utf8.encode('$line\n'));

  /// 模拟插件进程退出。
  void exitWith(int code) {
    if (!_exit.isCompleted) _exit.complete(code);
    unawaited(_out.close());
    unawaited(_err.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

PluginManifest _manifest() =>
    PluginManifest.fromJson({'id': 'demo', 'name': '示例插件'});

void main() {
  // ── 先把这个修复的**依据**本身钉住 ──
  //
  // 「用单订阅控制器而不是 broadcast」不是一个风格选择，而是正确性问题：
  // broadcast 控制器在没有监听者时会把事件丢掉，而插件进程完全可能在
  // 管理器挂上监听之前就写完 ready 并退出。下面的两条断言把这个语义差异
  // 固定下来，避免以后有人「顺手」把它改回 broadcast。
  group('流控制器的事件语义（修复的依据）', () {
    test('broadcast 控制器会丢掉「尚无监听者」期间的事件', () async {
      final broadcast = StreamController<int>.broadcast();
      broadcast.add(7);
      await broadcast.close();

      // 事件已经发生，但当时没人听 → 永久丢失。
      expect(await broadcast.stream.toList(), isEmpty);
    });

    test('单订阅控制器会把「尚无监听者」期间的事件缓存下来', () async {
      final single = StreamController<int>();
      single.add(7);
      // **不能 await close()**：单订阅控制器的 `close()` 返回的 future
      // 要等 done 事件被监听者消费完才完成，而此刻还没有任何监听者，
      // await 它会直接死等到测试超时。（broadcast 控制器没有这个语义，
      // 所以上面那条可以 await ——这个差异本身也是它俩不能用混的原因之一。）
      unawaited(single.close());

      // 监听者晚到也能拿到，这正是握手与退出码需要的语义。
      expect(await single.stream.toList(), [7]);
    });
  });

  group('插件进程事件不丢失', () {
    test('在订阅之前发出的 ready 仍能被收到', () async {
      final fake = _FakeProcess();
      final process = PluginProcess(
        manifest: _manifest(),
        process: fake,
        onDiagnostic: (_) {},
      );

      // 关键时序：**先**让插件回应握手，**再**挂监听。
      // 这正是真实链路的样子——`startProcess` 返回给管理器、管理器才
      // 走到 `process.messages.listen(...)`，中间必然隔着若干次事件循环。
      fake.writeLine('{"type":"ready","payload":{}}');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final ready = await process.messages.first;
      expect(ready.type, PluginMessageType.ready);
    });

    test('在订阅之前发生的退出仍能被收到，且退出码可查', () async {
      final fake = _FakeProcess();
      final process = PluginProcess(
        manifest: _manifest(),
        process: fake,
        onDiagnostic: (_) {},
      );

      // 解释器起不来时进程会瞬间退出——早于管理器订阅。
      // 丢掉这个事件的表现是插件永远停在「启动中」，既不显示崩溃原因，
      // 也不会触发有限次自动重启，用户只看到「插件没反应」。
      fake.exitWith(2);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(await process.exits.first, 2);
      expect(process.exitCode, 2);
      expect(process.isRunning, isFalse);
    });

    test('非 JSON 的 stdout 行按插件日志处理，不会污染协议流', () async {
      final fake = _FakeProcess();
      final process = PluginProcess(
        manifest: _manifest(),
        process: fake,
        onDiagnostic: (_) {},
      );

      // 插件作者习惯用 print 调试，这些行必须变成日志而不是被丢掉，
      // 更不能被当成协议消息（那会让主程序对着一行中文报解析错误）。
      fake.writeLine('随便 print 一行');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final log = await process.logLines.first;
      expect(log.type, PluginMessageType.log);
      expect(log.payload['message'], '随便 print 一行');
      expect(log.payload['tag'], 'stdout');
    });
  });
}
