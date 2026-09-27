import 'package:flutter_test/flutter_test.dart';
import 'package:lavedevelop/core/logging/log_service.dart';
import 'package:lavedevelop/domain/models/plugin_models.dart';
import 'package:lavedevelop/plugins/plugin_manager.dart';

/// 内存版文档存储。
///
/// 只实现 [JsonDocStoreLike] 声明的那两个方法——插件状态存储用到的就这些。
class _MemoryDocStore implements JsonDocStoreLike {
  final Map<String, List<Map<String, dynamic>>> lists = {};

  @override
  Future<List<Map<String, dynamic>>> readList(String key) async =>
      lists[key] ?? const [];

  @override
  Future<void> writeList(String key, List<Map<String, dynamic>> items) async {
    // 存副本：真实实现也是序列化后写入，共享引用会掩盖掉持久化本身的问题。
    lists[key] = items.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

/// 内存版插件状态存储。
class _MemoryPluginStore implements PluginStateStoreLike {
  final Map<String, Set<String>> sets = {};
  final Map<String, Map<String, int>> intMaps = {};
  final Map<String, Map<String, Object?>> jsonMaps = {};

  @override
  Future<Set<String>> readSet(String key) async => sets[key] ?? {};

  @override
  Future<void> writeSet(String key, Set<String> values) async =>
      sets[key] = {...values};

  @override
  Future<Map<String, int>> readIntMap(String key) async =>
      intMaps[key] ?? {};

  @override
  Future<void> writeIntMap(String key, Map<String, int> values) async =>
      intMaps[key] = {...values};

  @override
  Future<Map<String, Object?>> readJsonMap(String key) async =>
      jsonMaps[key] ?? {};

  @override
  Future<void> writeJsonMap(String key, Map<String, Object?> values) async =>
      jsonMaps[key] = {...values};
}

PluginManager _manager(PluginStateStoreLike store) =>
    PluginManager(log: LogService(), store: store);

void main() {
  group('插件清单（协议 v2）', () {
    test('解析 protocol_version 与配置声明', () {
      final manifest = PluginManifest.fromJson({
        'id': 'demo',
        'name': '示例',
        'protocol_version': 2,
        'config': [
          {
            'key': 'trigger',
            'label': '触发前缀',
            'type': 'string',
            'default': '#hi',
            'required': true,
          },
          {'label': '没有 key，应被跳过'},
        ],
      });

      expect(manifest.protocolVersion, 2);
      expect(manifest.isProtocolSupported, isTrue);
      expect(manifest.config, hasLength(1), reason: '缺少 key 的配置项应被跳过');
      expect(manifest.config.first.key, 'trigger');
      expect(manifest.configDefaults, {'trigger': '#hi'});
    });

    test('协议版本高于主程序时不兼容', () {
      final future = PluginManifest.fromJson({
        'id': 'x',
        'name': 'x',
        'protocol_version': pluginProtocolVersion + 1,
      });
      expect(future.isProtocolSupported, isFalse);
    });

    test('旧协议版本仍然兼容（旧插件能跑就不要拦住它）', () {
      final old = PluginManifest.fromJson({
        'id': 'x',
        'name': 'x',
        'protocol_version': 1,
      });
      expect(old.isProtocolSupported, isTrue);
    });

    test('未声明协议版本时按当前版本处理', () {
      final manifest = PluginManifest.fromJson({'id': 'x', 'name': 'x'});
      expect(manifest.protocolVersion, pluginProtocolVersion);
    });

    test('未知配置类型退化为多行文本，而不是丢掉该项', () {
      final field = PluginConfigField.fromJson({
        'key': 'k',
        'label': 'l',
        'type': '未来才有的类型',
      });
      expect(field.type, PluginConfigType.text);
    });

    test('必填项的「空」判定', () {
      const required = PluginConfigField(key: 'k', label: 'l', required: true);
      const optional = PluginConfigField(key: 'k', label: 'l');
      expect(required.isBlank(''), isTrue);
      expect(required.isBlank('   '), isTrue);
      expect(required.isBlank(null), isTrue);
      expect(required.isBlank('x'), isFalse);
      // 非必填项永远不算「空」：否则不填就会被拒绝启动。
      expect(optional.isBlank(null), isFalse);
    });

    test('订阅判定：空列表＝订阅全部', () {
      const all = PluginManifest(id: 'x', name: 'x');
      const some = PluginManifest(
        id: 'x',
        name: 'x',
        events: ['GROUP_AT_MESSAGE_CREATE'],
      );
      expect(all.subscribesToAll, isTrue);
      expect(all.subscribesTo('任意事件'), isTrue);
      expect(some.subscribesTo('GROUP_AT_MESSAGE_CREATE'), isTrue);
      expect(some.subscribesTo('C2C_MESSAGE_CREATE'), isFalse);
    });
  });

  group('配置类型解析', () {
    test('按类型解析用户输入', () {
      expect(PluginConfigType.string.parse(' x '), 'x');
      expect(PluginConfigType.integer.parse('42'), 42);
      expect(PluginConfigType.number.parse('1.5'), 1.5);
      expect(PluginConfigType.boolean.parse('true'), isTrue);
      expect(PluginConfigType.boolean.parse('false'), isFalse);
    });

    test('解析失败不抛异常，原样返回给界面去提示', () {
      // 一个手滑的数字不该让整张表单崩掉。
      expect(PluginConfigType.integer.parse('abc'), 'abc');
      expect(PluginConfigType.integer.parse(''), isNull);
    });

    test('值渲染回表单文本', () {
      expect(PluginConfigType.boolean.render(true), 'true');
      expect(PluginConfigType.integer.render(7), '7');
      expect(PluginConfigType.string.render(null), '');
    });
  });

  group('插件状态机', () {
    test('可启动状态包含崩溃与卡死', () {
      expect(PluginStatus.crashed.canStart, isTrue);
      expect(PluginStatus.hung.canStart, isTrue);
      expect(PluginStatus.stopped.canStart, isTrue);
      expect(PluginStatus.running.canStart, isFalse);
    });

    test('进程态包含「卡死」与「停止中」', () {
      // 卡死的进程还活着、还占着内存，界面必须按「有进程」处理，
      // 否则用户看不到「停止」按钮，只能干等。
      expect(PluginStatus.hung.hasProcess, isTrue);
      expect(PluginStatus.stopping.hasProcess, isTrue);
      expect(PluginStatus.crashed.hasProcess, isFalse);
    });

    test('卡死与崩溃都算异常态', () {
      expect(PluginStatus.hung.isFailure, isTrue);
      expect(PluginStatus.crashed.isFailure, isTrue);
      expect(PluginStatus.stopped.isFailure, isFalse);
    });

    test('状态标签与文档里那张表逐字一致', () {
      // 文档 plugins/lifecycle.md 有张状态表，界面也直接显示这些中文。
      // 这里做一次「文案即契约」的锁：改了标签必须同步改文档，否则
      // 用户在文档里搜不到界面上看到的那几个字。
      expect(
        PluginStatus.values.map((e) => e.label).toList(),
        ['已禁用', '未启动', '启动中', '运行中', '无响应', '停止中', '已崩溃', '平台不支持'],
      );
    });
  });

  group('插件快照 copyWith 的重置语义', () {
    PluginDescriptor descriptor() => const PluginDescriptor(
          manifest: PluginManifest(id: 'demo', name: '示例'),
          status: PluginStatus.crashed,
          restartCount: 2,
          missedPongs: 3,
          pid: 1234,
          lastError: '崩了',
        );

    test('计数可以被显式重置为 0', () {
      // `x ?? this.x` 的写法一旦写成 `x == 0 ? this.x : x`（或用 `??=`），
      // 「重启」就再也清不掉自动重启预算，而这类 bug 在界面上表现为
      // 「按了重启也没用」，极难定位。这里把重置能力钉住。
      final reset = descriptor().copyWith(restartCount: 0, missedPongs: 0);
      expect(reset.restartCount, 0);
      expect(reset.missedPongs, 0);
    });

    test('不传的字段保持原值', () {
      final same = descriptor().copyWith(status: PluginStatus.running);
      expect(same.restartCount, 2);
      expect(same.missedPongs, 3);
      expect(same.pid, 1234);
      expect(same.lastError, '崩了');
    });

    test('pid 与错误信息要能单独清除', () {
      final cleared = descriptor().copyWith(clearPid: true, clearError: true);
      expect(cleared.pid, isNull);
      expect(cleared.lastError, isNull);
    });
  });

  group('心跳判定契约', () {
    test('默认参数对应「连续 3 次无响应 ≈ 90 秒静默」', () async {
      // 文档 plugins/lifecycle.md 与 plugins/protocol.md 都写着
      // 「连续 3 次无响应（约 90 秒）」；判定逻辑里若把 `>=` 写成 `>`，
      // 实际要等到第 4 个周期才动手，比声称的多一个心跳间隔。
      // 这里锁住参数本身，逻辑侧由 `_startPing` 的注释与实现保证一致。
      final manager = _manager(_MemoryPluginStore());
      expect(manager.pingInterval, const Duration(seconds: 30));
      expect(manager.maxMissedPongs, 3);
      expect(
        manager.pingInterval * manager.maxMissedPongs,
        const Duration(seconds: 90),
      );
    });

    test('握手超时与文档一致的 20 秒', () async {
      final manager = _manager(_MemoryPluginStore());
      expect(manager.handshakeTimeout, const Duration(seconds: 20));
    });
  });

  group('协议消息', () {
    test('state_set 的状态对象是顶层合并语义', () {
      final message = PluginMessage.fromJson({
        'type': 'state_set',
        'payload': {
          'state': {'count': 3},
        },
      });
      expect(message.type, PluginMessageType.stateSet);
      expect(message.statePayload, {'count': 3});
    });

    test('state_remove 解析要删除的键', () {
      final message = PluginMessage.fromJson({
        'type': 'state_remove',
        'payload': {
          'keys': ['a', 'b'],
        },
      });
      expect(message.stateRemoveKeys, ['a', 'b']);
    });

    test('新增的消息类型都能往返', () {
      for (final type in [
        PluginMessageType.ready,
        PluginMessageType.pong,
        PluginMessageType.stateSet,
        PluginMessageType.stateRemove,
        PluginMessageType.configUpdate,
      ]) {
        expect(PluginMessageType.fromWire(type.wireName), type);
      }
    });

    test('未知类型退化为日志，不丢内容', () {
      final message = PluginMessage.fromJson({
        'type': '未来才有的类型',
        'payload': {'message': 'hello'},
      });
      expect(message.type, PluginMessageType.log);
      expect(message.logMessage, 'hello');
    });
  });

  group('状态存储往返', () {
    test('JsonPluginStateStore 的 JSON 映射能存能读', () async {
      final store = JsonPluginStateStore(store: _MemoryDocStore());
      await store.writeJsonMap('state_demo', {
        'count': 3,
        'enabled': true,
        'nested': {'a': 1},
      });

      final restored = await store.readJsonMap('state_demo');
      expect(restored['count'], 3);
      expect(restored['enabled'], true);
      expect(restored['nested'], {'a': 1});
    });

    test('未写入过的键返回空表而不是抛异常', () async {
      final store = JsonPluginStateStore(store: _MemoryDocStore());
      expect(await store.readJsonMap('不存在'), isEmpty);
    });
  });

  group('插件包导入的拒绝路径', () {
    // 这些用例覆盖的校验都发生在落地写文件**之前**，
    // 因此不需要文件系统即可验证。
    test('非插件包被拒绝', () async {
      final manager = _manager(_MemoryPluginStore());
      expect(await manager.importBundle({'foo': 'bar'}), contains('lave_plugin_bundle'));
    });

    test('插件 ID 不合法被拒绝（含路径穿越）', () async {
      final manager = _manager(_MemoryPluginStore());
      for (final bad in ['../evil', 'a/b', '..', '', '带中文']) {
        final error = await manager.importBundle({
          'lave_plugin_bundle': 1,
          'id': bad,
          'files': {'plugin.json': '{}'},
        });
        expect(error, isNotNull, reason: 'ID「$bad」不应被接受');
      }
    });

    test('没有文件或缺少 plugin.json 被拒绝', () async {
      final manager = _manager(_MemoryPluginStore());
      expect(
        await manager.importBundle({
          'lave_plugin_bundle': 1,
          'id': 'demo',
          'files': <String, dynamic>{},
        }),
        contains('没有文件'),
      );
      expect(
        await manager.importBundle({
          'lave_plugin_bundle': 1,
          'id': 'demo',
          'files': {'main.py': 'print(1)'},
        }),
        contains('plugin.json'),
      );
    });

    test('包内非法路径被拒绝', () async {
      final manager = _manager(_MemoryPluginStore());
      final error = await manager.importBundle({
        'lave_plugin_bundle': 1,
        'id': 'demo',
        'files': {
          'plugin.json': '{}',
          '../../evil.py': 'print(1)',
        },
      });
      expect(error, contains('非法路径'));
    });
  });
}
