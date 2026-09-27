import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/app_services.dart';
import '../../app/theme.dart';
import '../../domain/models/log_entry.dart';
import '../../domain/models/plugin_models.dart';
import '../../plugins/plugin_manager.dart';
import '../../shared/widgets/glass.dart';

/// 插件 Tab。
///
/// 三件事必须在这一页说清楚，否则用户无从下手：
/// 1. **平台能力**：iOS 上根本无法创建子进程，Android 上系统也没有 Python，
///    结论不摆出来，用户只会看到「开关点了没反应」；
/// 2. **每个插件的真实状态**：卡死与崩溃是两种不同故障，界面要能区分；
/// 3. **配置与文件**：插件要能用、能改，就必须能在手机上配置与编辑，
///    而不是让人把手机连到电脑上改文件。
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
              tooltip: '安装示例插件',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: _busy ? null : _installExample,
            ),
            IconButton(
              tooltip: '刷新插件目录',
              icon: const Icon(Icons.refresh),
              onPressed: _busy ? null : _refresh,
            ),
          ],
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : _importFromClipboard,
            icon: const Icon(Icons.download_outlined),
            label: const Text('导入插件'),
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
                            isDark:
                                Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                      )
                    : null,
              ),
              if (plugins.isEmpty)
                const GlassEmptyState(
                  icon: Icons.extension_outlined,
                  title: '还没有安装插件',
                  description: '插件是独立的 Python 进程，通过 JSON 行协议与主程序通信，'
                      '单个插件崩溃不会影响机器人本体。\n\n'
                      '可以点右上角安装内置示例插件，或用右下角从剪贴板导入一个插件包。',
                )
              else
                for (final (index, plugin) in plugins.indexed)
                  FadeSlideIn(
                    // 错落延迟最多累加到第 6 个：再多会让整页显得「慢吞吞」。
                    delay: Duration(milliseconds: 40 * index.clamp(0, 5)),
                    child: _PluginCard(
                      services: services,
                      plugin: plugin,
                      supported: manager.isSupported,
                      onToggle: (value) => manager.setEnabled(plugin.id, value),
                      onStart: () => manager.start(plugin.id),
                      onRestart: () => manager.restart(plugin.id),
                      onStop: () => manager.stop(plugin.id),
                      onDelete: () => _confirmDelete(plugin),
                      onOpenConfig: () => _openConfig(plugin),
                      onOpenFiles: () => _openFiles(plugin),
                      onExport: () => _export(plugin),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  // ───────────────────────── 页级动作 ─────────────────────────

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await ref.read(appServicesProvider).plugins.refresh();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _installExample() async {
    setState(() => _busy = true);
    final error = await ref.read(appServicesProvider).plugins
        .installBundledExample();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      _toast(error);
      return;
    }
    // 安装完顺手把开关打开：示例插件的意义就是「能被验证」，
    // 让人装完再去翻开关是多一步无谓的操作。
    await ref
        .read(appServicesProvider)
        .plugins
        .setEnabled('demo_plugin', true);
    if (!mounted) return;
    _toast('示例插件已安装并启用。它的日志会出现在「日志」页。');
  }

  Future<void> _importFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      _toast('剪贴板是空的。请先复制插件包 JSON。');
      return;
    }

    Map<String, dynamic>? bundle;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) bundle = decoded.cast<String, dynamic>();
    } catch (_) {
      // 落到下面统一提示。
    }
    if (bundle == null) {
      _toast('剪贴板内容不是合法的 JSON 插件包。');
      return;
    }

    setState(() => _busy = true);
    final error = await ref.read(appServicesProvider).plugins.importBundle(bundle);
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(error ?? '导入完成。它默认是关闭的，需要手动启用。');
  }

  Future<void> _export(PluginDescriptor plugin) async {
    final bundle =
        await ref.read(appServicesProvider).plugins.exportBundle(plugin.id);
    await Clipboard.setData(
      ClipboardData(text: jsonEncode(bundle)),
    );
    if (!mounted) return;
    _toast('已把「${plugin.manifest.name}」复制为插件包 JSON，粘贴保存即可备份或分享。');
  }

  Future<void> _confirmDelete(PluginDescriptor plugin) async {
    final services = ref.read(appServicesProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除插件'),
        content: Text(
          '将停止「${plugin.manifest.name}」并删除其整个目录、配置与状态，不可撤销。',
        ),
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

  Future<void> _openConfig(PluginDescriptor plugin) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConfigSheet(
        services: ref.read(appServicesProvider),
        plugin: plugin,
      ),
    );
  }

  Future<void> _openFiles(PluginDescriptor plugin) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FileSheet(
        services: ref.read(appServicesProvider),
        plugin: plugin,
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent =
        supported ? const Color(0xFF2E9E6B) : const Color(0xFFD08A1E);
    return GlassPanel(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PulseDot(color: accent, size: 8, animate: supported),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  supported ? '运行环境就绪（$running 个运行中）' : '当前平台无法运行插件',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: GlassTheme.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            describe,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.65,
              color: GlassTheme.textSecondary(context),
            ),
          ),
          if (!supported && reason != null) ...[
            const SizedBox(height: 6),
            Text(
              '插件是独立的 Python 子进程，主程序无法在不支持子进程或不带 '
              'Python 的平台上运行它们。这不是配置问题。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: GlassTheme.levelColor('WARN', isDark: isDark),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个插件卡片。
class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.services,
    required this.plugin,
    required this.supported,
    required this.onToggle,
    required this.onStart,
    required this.onRestart,
    required this.onStop,
    required this.onDelete,
    required this.onOpenConfig,
    required this.onOpenFiles,
    required this.onExport,
  });

  final AppServices services;
  final PluginDescriptor plugin;
  final bool supported;
  final ValueChanged<bool> onToggle;
  final Future<void> Function() onStart;

  /// 用户显式重启：会重置自动重启预算（见 `PluginManager.restart`）。
  ///
  /// 与 [onStart] 分开是必要的——「启动」不该动预算，
  /// 否则自动重启的退避上限会被用户的一次点击意外解除。
  final Future<void> Function() onRestart;
  final Future<void> Function() onStop;
  final Future<void> Function() onDelete;
  final VoidCallback onOpenConfig;
  final VoidCallback onOpenFiles;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = _accentFor(plugin.status);
    final manifest = plugin.manifest;

    return GlassExpandableCard(
      title: manifest.name,
      subtitle: _subtitle(),
      accent: accent,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
            ),
            child: Icon(_iconFor(plugin.status), size: 16, color: accent),
          ),
          if (plugin.status == PluginStatus.starting ||
              plugin.status == PluginStatus.stopping)
            Positioned(
              right: -3,
              top: -3,
              child: PulseDot(color: accent, size: 8),
            ),
        ],
      ),
      trailing: Switch(value: plugin.enabled, onChanged: onToggle),
      children: [
        if (manifest.description != null)
          Text(
            manifest.description!,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        const SizedBox(height: 6),
        _InfoRow(label: '插件 ID', value: manifest.id),
        if (manifest.version != null)
          _InfoRow(label: '版本', value: manifest.version!),
        if (manifest.author != null)
          _InfoRow(label: '作者', value: manifest.author!),
        _InfoRow(
          label: '协议版本',
          value: 'v${manifest.protocolVersion}'
              '${manifest.isProtocolSupported ? '' : '（高于本程序支持的版本，已拒绝加载）'}',
        ),
        _InfoRow(
          label: '事件订阅',
          value: manifest.subscribesToAll
              ? '全部事件'
              : manifest.events.join('、'),
        ),
        if (plugin.pid != null) _InfoRow(label: 'PID', value: '${plugin.pid}'),
        if (plugin.lastReadyAt != null)
          _InfoRow(
            label: '就绪于',
            value: LogEntry.formatDateTime(plugin.lastReadyAt!),
          ),
        if (plugin.lastPongAt != null)
          _InfoRow(
            label: '最近心跳',
            value: LogEntry.formatDateTime(plugin.lastPongAt!),
          ),
        if (plugin.sentEvents > 0)
          _InfoRow(label: '已投递', value: '${plugin.sentEvents} 个事件'),
        if (plugin.crashCount > 0)
          _InfoRow(
            label: '崩溃次数',
            value: '${plugin.crashCount}${plugin.isFlapping ? '（反复崩溃）' : ''}',
          ),
        if (plugin.restartCount > 0)
          _InfoRow(label: '自动重启', value: '${plugin.restartCount} 次'),
        if (plugin.droppedLogs > 0)
          _InfoRow(
            label: '丢弃日志',
            value: '${plugin.droppedLogs} 行（输出过快，已限流）',
          ),
        if (plugin.lastError != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: GlassTheme.levelColor('ERROR', isDark: isDark)
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              plugin.lastError!,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: GlassTheme.levelColor('ERROR', isDark: isDark),
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (plugin.status.canStart)
              GlassButton(
                label: plugin.status == PluginStatus.crashed ||
                        plugin.status == PluginStatus.hung
                    ? '重启'
                    : '启动',
                icon: Icons.play_arrow_rounded,
                dense: true,
                // 崩溃/无响应时的「重启」要重置自动重启预算，
                // 否则一个已经用光退避额度的插件按了重启也不会再自愈。
                onPressed: supported
                    ? () => plugin.status == PluginStatus.crashed ||
                            plugin.status == PluginStatus.hung
                        ? onRestart()
                        : onStart()
                    : null,
              ),
            if (plugin.status.hasProcess)
              GlassButton(
                label: '停止',
                icon: Icons.stop_rounded,
                dense: true,
                onPressed: () => onStop(),
              ),
            GlassButton(
              label: '配置${manifest.config.isEmpty ? '' : '（${manifest.config.length}）'}',
              icon: Icons.tune,
              dense: true,
              onPressed: manifest.config.isEmpty ? null : onOpenConfig,
            ),
            GlassButton(
              label: '文件',
              icon: Icons.folder_open_outlined,
              dense: true,
              onPressed: onOpenFiles,
            ),
            GlassButton(
              label: '导出',
              icon: Icons.ios_share,
              dense: true,
              onPressed: onExport,
            ),
            GlassButton(
              label: '删除',
              icon: Icons.delete_outline,
              dense: true,
              onPressed: () => onDelete(),
            ),
          ],
        ),
        if (manifest.config.isEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '这个插件没有声明配置项。插件可以在 plugin.json 的 config 里声明，'
            '声明后此处会出现一个表单。',
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: GlassTheme.textSecondary(context),
            ),
          ),
        ],
      ],
    );
  }

  String _subtitle() {
    final parts = <String>[plugin.status.label];
    if (plugin.enabled && !plugin.status.hasProcess) {
      parts.add('已启用');
    }
    if (plugin.lastStartedAt != null) {
      parts.add('启动于 ${LogEntry.formatTime(plugin.lastStartedAt!)}');
    }
    if (plugin.lastError != null && plugin.status.isFailure) {
      parts.add(plugin.lastError!);
    }
    return parts.join(' · ');
  }

  static IconData _iconFor(PluginStatus status) {
    switch (status) {
      case PluginStatus.running:
        return Icons.play_circle_outline;
      case PluginStatus.starting:
      case PluginStatus.stopping:
        return Icons.hourglass_empty;
      case PluginStatus.hung:
        return Icons.hourglass_disabled_outlined;
      case PluginStatus.crashed:
        return Icons.error_outline;
      case PluginStatus.unsupported:
        return Icons.block;
      case PluginStatus.disabled:
      case PluginStatus.stopped:
        return Icons.pause_circle_outline;
    }
  }

  static Color _accentFor(PluginStatus status) {
    switch (status) {
      case PluginStatus.running:
        return const Color(0xFF2E9E6B);
      case PluginStatus.starting:
      case PluginStatus.stopping:
        return const Color(0xFFD08A1E);
      case PluginStatus.crashed:
      case PluginStatus.hung:
        return const Color(0xFFD04A3E);
      case PluginStatus.unsupported:
        return const Color(0xFF7A7A8C);
      case PluginStatus.disabled:
      case PluginStatus.stopped:
        return const Color(0xFF7A8CA0);
    }
  }
}

/// 信息行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: GlassTheme.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                color: GlassTheme.textPrimary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 配置表单。
///
/// 表单完全由插件的 `config` 声明生成——用户不需要知道配置存在哪、
/// 长什么样；插件作者也不必自己解析命令行或环境变量。
class _ConfigSheet extends StatefulWidget {
  const _ConfigSheet({required this.services, required this.plugin});

  final AppServices services;
  final PluginDescriptor plugin;

  @override
  State<_ConfigSheet> createState() => _ConfigSheetState();
}

class _ConfigSheetState extends State<_ConfigSheet> {
  final Map<String, TextEditingController> _controllers = {};
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (final field in widget.plugin.manifest.config) {
      _controllers[field.key] = TextEditingController();
    }
    _load();
  }

  Future<void> _load() async {
    final values = await widget.services.plugins.configOf(widget.plugin.id);
    if (!mounted) return;
    setState(() {
      for (final field in widget.plugin.manifest.config) {
        _controllers[field.key]?.text = field.type.render(values[field.key]);
      }
      _loaded = true;
    });
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14192B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '配置 · ${widget.plugin.manifest.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '保存后若插件正在运行，会立刻收到新配置，不需要重启。',
                style: TextStyle(
                  fontSize: 11.5,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 12),
              if (!_loaded)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                for (final field in widget.plugin.manifest.config)
                  _fieldRow(field, isDark),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving || !_loaded ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(PluginConfigField field, bool isDark) {
    final controller = _controllers[field.key]!;
    final multiline = field.type == PluginConfigType.text;

    final input = TextField(
      controller: controller,
      maxLines: multiline ? 4 : 1,
      keyboardType: switch (field.type) {
        PluginConfigType.integer => TextInputType.number,
        PluginConfigType.number => const TextInputType.numberWithOptions(
            decimal: true,
          ),
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.description,
        helperMaxLines: 3,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (field.type == PluginConfigType.boolean)
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        field.label,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: controller.text == 'true',
                        onChanged: (value) => setState(() {
                          controller.text = value ? 'true' : 'false';
                        }),
                      ),
                    ],
                  ),
                )
              else
                Expanded(child: input),
              if (field.required)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    '必填',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: GlassTheme.levelColor('WARN', isDark: isDark),
                    ),
                  ),
                ),
            ],
          ),
          if (field.type == PluginConfigType.boolean &&
              field.description != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                field.description!,
                style: TextStyle(
                  fontSize: 11.5,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
            ),
          if (field.type != PluginConfigType.boolean)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '键名：${field.key}',
                style: TextStyle(
                  fontSize: 11,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final values = <String, Object?>{};
    for (final field in widget.plugin.manifest.config) {
      final raw = _controllers[field.key]!.text;
      final parsed = field.type.parse(raw);
      values[field.key] = parsed;
      if (field.isBlank(parsed)) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${field.label}」是必填项')),
        );
        return;
      }
    }
    await widget.services.plugins.setConfig(widget.plugin.id, values);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('配置已保存')),
    );
  }
}

/// 文件管理。
///
/// 存在的理由很实际：Android 11 起应用私有目录不再对文件管理器可见，
/// 没有这一层的话「在手机上改一行插件代码」这件事根本无法完成。
class _FileSheet extends StatefulWidget {
  const _FileSheet({required this.services, required this.plugin});

  final AppServices services;
  final PluginDescriptor plugin;

  @override
  State<_FileSheet> createState() => _FileSheetState();
}

class _FileSheetState extends State<_FileSheet> {
  List<String> _files = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await widget.services.plugins.listFiles(widget.plugin.id);
    if (!mounted) return;
    setState(() {
      _files = files;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14192B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '文件 · ${widget.plugin.manifest.name}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '只列出插件源码文件（不含运行时数据目录）。'
                '可编辑 ${PluginManager.editableExtensions.map((e) => '.$e').join(' ')}，'
                '单文件上限 ${PluginManager.maxEditableFileBytes ~/ 1024}KB。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: GlassTheme.textSecondary(context),
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_files.isEmpty)
                Text(
                  '插件目录里没有文件。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: GlassTheme.textSecondary(context),
                  ),
                )
              else
                for (final file in _files) _fileRow(file),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyPath,
                      icon: const Icon(Icons.copy_all_outlined, size: 16),
                      label: const Text('复制插件目录路径'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _newFile,
                      icon: const Icon(Icons.note_add_outlined, size: 16),
                      label: const Text('新建文件'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fileRow(String file) {
    final extension = file.split('.').last.toLowerCase();
    final editable = PluginManager.editableExtensions.contains(extension);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        editable ? Icons.description_outlined : Icons.insert_drive_file_outlined,
        size: 20,
      ),
      title: Text(file, style: const TextStyle(fontSize: 13)),
      subtitle: editable ? null : const Text('不可在应用内编辑', style: TextStyle(fontSize: 11)),
      trailing: editable
          ? const Icon(Icons.edit_outlined, size: 18)
          : null,
      onTap: editable ? () => _edit(file) : null,
    );
  }

  Future<void> _copyPath() async {
    final path = await widget.services.plugins
        .pluginDirectoryPath(widget.plugin.id);
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制：$path')),
    );
  }

  Future<void> _edit(String file) async {
    final content = await widget.services.plugins
        .readPluginFile(widget.plugin.id, file);
    if (!mounted) return;
    if (content == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个文件无法以文本方式读取')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorSheet(
        services: widget.services,
        pluginId: widget.plugin.id,
        fileName: file,
        initial: content,
        onSaved: _load,
      ),
    );
  }

  Future<void> _newFile() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('新建文件'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '相对路径',
            hintText: '例如 helper.py',
            helperText: '只允许在插件目录内创建',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;

    final error =
        await widget.services.plugins.createPluginFile(widget.plugin.id, name);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await _load();
  }
}

/// 单文件编辑器。
class _EditorSheet extends StatefulWidget {
  const _EditorSheet({
    required this.services,
    required this.pluginId,
    required this.fileName,
    required this.initial,
    required this.onSaved,
  });

  final AppServices services;
  final String pluginId;
  final String fileName;
  final String initial;
  final Future<void> Function() onSaved;

  @override
  State<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends State<_EditorSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  bool _dirty = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF14192B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
            Text(
              _dirty ? '有未保存的修改' : '改动会在保存后写回磁盘；插件需要重启才会加载新代码。',
              style: TextStyle(
                fontSize: 11.5,
                color: _dirty
                    ? GlassTheme.levelColor('WARN', isDark: isDark)
                    : GlassTheme.textSecondary(context),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                onChanged: (_) {
                  if (!_dirty) setState(() => _dirty = true);
                },
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final error = await widget.services.plugins.writePluginFile(
      widget.pluginId,
      widget.fileName,
      _controller.text,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = error != null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? '已保存')),
    );
    if (error == null) await widget.onSaved();
  }
}
