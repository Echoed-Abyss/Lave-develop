import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../domain/models/log_entry.dart';
import '../../domain/models/plugin_models.dart';
import '../../shared/widgets/glass.dart';

/// 插件 Tab。
///
/// 这一页最重要的信息是**平台能力**：iOS 上根本无法创建子进程，
/// Android 上系统也没有 Python。如果不把结论明确显示出来，
/// 用户只会看到「插件开关点了没反应」，然后以为是自己配错了。
class PluginsPage extends ConsumerStatefulWidget {
  const PluginsPage({super.key});

  @override
  ConsumerState<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends ConsumerState<PluginsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);

    return ListenableBuilder(
      listenable: services.plugins,
      builder: (context, _) {
        final manager = services.plugins;
        final plugins = manager.plugins;

        return GlassScaffold(
          title: '插件',
          actions: [
            IconButton(
              tooltip: '重新扫描插件目录',
              icon: const Icon(Icons.refresh),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await manager.refresh();
                      if (mounted) setState(() => _busy = false);
                    },
            ),
          ],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _createDemoPlugin,
            icon: const Icon(Icons.note_add_outlined),
            label: const Text('写入示例插件'),
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 96, top: 8),
            children: [
              FadeSlideIn(
                child: _CapabilityBanner(
                  supported: manager.isSupported,
                  describe: manager.capability.describe,
                  reason: manager.capability.reason,
                  running: manager.runningCount,
                ),
              ),
              GlassSectionTitle(
                text: '已安装（${plugins.length}）',
                trailing: manager.hasCrashed
                    ? Text(
                        '有插件异常',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: GlassTheme.levelColor(
                            'ERROR',
                            isDark: Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                      )
                    : null,
              ),
              if (plugins.isEmpty)
                const GlassEmptyState(
                  icon: Icons.extension_outlined,
                  title: '还没有安装插件',
                  description: '插件是独立的 Python 进程，通过 JSON 行协议与主程序通信。\n'
                      '单个插件崩溃不会影响机器人本体。\n\n'
                      '点击右下角可写入一个示例插件。',
                )
              else
                for (final (index, plugin) in plugins.indexed)
                  FadeSlideIn(
                    // 错落延迟最多累加到第 6 个：再多会让整页显得「慢吞吞」。
                    delay: Duration(milliseconds: 40 * index.clamp(0, 5)),
                    child: _PluginCard(
                      plugin: plugin,
                      supported: manager.isSupported,
                      onToggle: (value) => manager.setEnabled(plugin.id, value),
                      onStart: () => manager.start(plugin.id),
                      onStop: () => manager.stop(plugin.id),
                      onDelete: () => _confirmDelete(plugin),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(PluginDescriptor plugin) async {
    final services = ref.read(appServicesProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除插件'),
        content: Text('将停止「${plugin.manifest.name}」并删除其整个目录，不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await services.plugins.remove(plugin.id);
  }

  /// 写入一个可运行的示例插件。
  ///
  /// 存在的价值：让插件系统**可被验证**。否则「新建插件目录、写清单、
  /// 实现协议」这套流程没人愿意为了试一下而走一遍。
  Future<void> _createDemoPlugin() async {
    setState(() => _busy = true);
    final services = ref.read(appServicesProvider);
    try {
      final root = await services.plugins.pluginsDirectory();
      final dir = Directory(p.join(root.path, 'demo_plugin'));
      await dir.create(recursive: true);

      await File(p.join(dir.path, 'plugin.json')).writeAsString(
        _demoManifest,
      );
      await File(p.join(dir.path, 'main.py')).writeAsString(_demoScript);

      await services.plugins.refresh();
      services.log.info(
        LogSource.plugin,
        '已写入示例插件到 ${dir.path}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('示例插件已写入。在下方打开开关并启动即可看到它的日志输出。'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写入失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const String _demoManifest = '''
{
  "id": "demo_plugin",
  "name": "示例插件",
  "version": "1.0.0",
  "description": "演示插件协议：收到消息后记录日志，并对以 #hi 开头的消息回一句问候。",
  "author": "Lave",
  "entry": "main.py",
  "events": [],
  "enabled_by_default": false
}
''';

  static const String _demoScript = r'''
# -*- coding: utf-8 -*-
"""Lave 示例插件。

协议：一行一条 JSON（JSON Lines）。
- 主进程 -> 插件：{"type":"init"|"event"|"shutdown","id":"...","payload":{...}}
- 插件 -> 主进程：{"type":"ready"|"log"|"reply","id":"...","payload":{...}}

注意：
1. 必须使用 print + flush，或依赖主进程传入的 PYTHONUNBUFFERED=1；
2. 任何非 JSON 的 print 输出都会被当作日志收进「日志」Tab,不会丢；
3. 本进程崩溃只影响本插件，机器人本体不受影响。
"""
import json
import sys


def emit(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(message, level="info"):
    emit({"type": "log", "payload": {"level": level, "message": message}})


def main():
    log("示例插件已启动，等待事件")
    # 告知主进程握手完成。
    emit({"type": "ready", "payload": {}})

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except Exception as error:
            log("无法解析的指令行: %s (%s)" % (line, error), "warn")
            continue

        kind = message.get("type")
        if kind == "shutdown":
            log("收到停止指令，准备退出")
            break
        if kind == "init":
            manifest = (message.get("payload") or {}).get("manifest") or {}
            log("已加载插件 %s v%s" % (manifest.get("name"), manifest.get("version")))
            continue
        if kind == "event":
            payload = message.get("payload") or {}
            event = payload.get("event") or {}
            content = (event.get("content") or "").strip()
            log("收到事件 %s: %s" % (payload.get("t"), content))

            if content.startswith("#hi"):
                conversation_id = event.get("conversation_id")
                if conversation_id:
                    # 由主进程代发消息：插件永远拿不到 access_token。
                    emit({
                        "type": "reply",
                        "id": message.get("id"),
                        "payload": {
                            "bot_id": payload.get("bot_id"),
                            "conversation_id": conversation_id,
                            "scope": event.get("scope"),
                            "text": "你好，我是由 Python 插件发出的回复。",
                            "passive": True,
                            "msg_id": event.get("message_id"),
                            "event_id": event.get("event_id"),
                        },
                    })
    log("示例插件已退出")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        log("插件异常退出: %s" % error, "error")
        raise
''';
}

/// 平台能力横幅。
class _CapabilityBanner extends StatelessWidget {
  const _CapabilityBanner({
    required this.supported,
    required this.describe,
    required this.reason,
    required this.running,
  });

  final bool supported;
  final String describe;
  final String? reason;
  final int running;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      accent: supported ? const Color(0xFF2E9E6B) : const Color(0xFFD08A1E),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                supported ? Icons.check_circle_outline : Icons.info_outline,
                size: 17,
                color: supported
                    ? const Color(0xFF2E9E6B)
                    : const Color(0xFFD08A1E),
              ),
              const SizedBox(width: 7),
              Text(
                supported ? '插件可运行' : '当前平台无法运行插件',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: GlassTheme.textPrimary(context),
                ),
              ),
              const Spacer(),
              if (supported)
                Text(
                  '运行中 $running',
                  style: TextStyle(
                    fontSize: 12,
                    color: GlassTheme.textSecondary(context),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason == null ? describe : '$describe\n\n$reason',
            style: TextStyle(
              fontSize: 12,
              height: 1.65,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 插件卡片。
class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.plugin,
    required this.supported,
    required this.onToggle,
    required this.onStart,
    required this.onStop,
    required this.onDelete,
  });

  final PluginDescriptor plugin;
  final bool supported;
  final ValueChanged<bool> onToggle;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final manifest = plugin.manifest;
    return GlassExpandableCard(
      title: manifest.name.isEmpty ? plugin.id : manifest.name,
      subtitle: '${plugin.status.label}'
          '${manifest.version == null ? '' : ' · v${manifest.version}'}'
          '${plugin.pid == null ? '' : ' · PID ${plugin.pid}'}'
          '${plugin.crashCount > 0 ? ' · 崩溃 ${plugin.crashCount} 次' : ''}',
      accent: _accentFor(plugin.status),
      trailing: Switch(
        value: plugin.enabled,
        onChanged: supported ? onToggle : null,
      ),
      children: [
        if (manifest.description != null)
          Text(
            manifest.description!,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        if (plugin.lastError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              plugin.lastError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFD04A3E)),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            GlassButton(
              label: '启动',
              icon: Icons.play_arrow,
              dense: true,
              onPressed: !supported || plugin.isRunning ? null : onStart,
            ),
            GlassButton(
              label: '停止',
              icon: Icons.stop,
              dense: true,
              onPressed: !plugin.isRunning ? null : onStop,
            ),
            GlassButton(
              label: '删除',
              icon: Icons.delete_outline,
              dense: true,
              onPressed: onDelete,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '订阅事件：${manifest.subscribesToAll ? '全部' : manifest.events.join('、')}'
          '\n入口文件：${manifest.entry}',
          style: TextStyle(
            fontSize: 11.5,
            height: 1.6,
            color: GlassTheme.textSecondary(context),
          ),
        ),
      ],
    );
  }

  static Color _accentFor(PluginStatus status) {
    switch (status) {
      case PluginStatus.running:
        return const Color(0xFF2E9E6B);
      case PluginStatus.starting:
        return const Color(0xFFD08A1E);
      case PluginStatus.crashed:
        return const Color(0xFFD04A3E);
      case PluginStatus.unsupported:
        return const Color(0xFF7A7A8C);
      case PluginStatus.disabled:
      case PluginStatus.stopped:
        return const Color(0xFF7A8CA0);
    }
  }
}
