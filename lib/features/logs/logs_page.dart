import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/theme.dart';
import '../../domain/models/log_entry.dart';
import '../../shared/widgets/glass.dart';

/// 日志 Tab。
///
/// 这一页存在的意义不是「好看」：整个应用最难排查的两类问题
/// ——连接莫名断开、消息发不出去——都只能靠日志定位。
/// 因此这里把**官方错误码与 trace_id 直接展示出来**，
/// 它们是找平台协助时唯一有效的凭据。
class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});

  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  @override
  Widget build(BuildContext context) {
    final services = ref.watch(appServicesProvider);

    return ListenableBuilder(
      listenable: services.log,
      builder: (context, _) {
        final log = services.log;
        final entries = log.filtered;

        return GlassScaffold(
          title: '日志',
          actions: [
            IconButton(
              tooltip: '复制诊断信息',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: log.exportText()),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('诊断信息已复制到剪贴板')),
                );
              },
            ),
            IconButton(
              tooltip: '清空',
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: log.clear,
            ),
          ],
          body: Column(
            children: [
              _FilterBar(log: log),
              if (log.droppedCount > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '更早的 ${log.droppedCount} 条日志已省略'
                      '（内存上限 ${log.maxEntries} 条）',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: GlassTheme.textSecondary(context),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: entries.isEmpty
                    ? const GlassEmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: '暂无日志',
                        description: '连接、收发消息、插件输出都会记录在这里。',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24, top: 4),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          return GlassLogItem(
                            entry: entry,
                            onTap: () => _showDetail(context, entry),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDetail(BuildContext context, LogEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${entry.level.label} · ${entry.source.label}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('时间', LogEntry.formatDateTime(entry.at)),
              if (entry.botId != null) _kv('机器人', entry.botId!),
              if (entry.pluginId != null) _kv('插件', entry.pluginId!),
              // 官方错误码：排查的第一手信息，必须完整展示。
              if (entry.officialCode != null)
                _kv('官方错误码', '${entry.officialCode}'),
              if (entry.traceId != null) _kv('trace_id', entry.traceId!),
              const SizedBox(height: 8),
              SelectableText(entry.message),
              if (entry.detail != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  entry.detail!,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(
                key,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );
}

/// 筛选条。
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.log});

  final dynamic log;

  @override
  Widget build(BuildContext context) {
    final counts = log.countsBySource as Map<LogSource, int>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final level in LogLevel.values)
                GlassChip(
                  label: level.label,
                  selected: log.minLevel == level,
                  onTap: () => log.setFilter(minLevel: level),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              GlassChip(
                label: '全部来源',
                selected: log.sourceFilter == null,
                onTap: () => log.setFilter(clearSource: true),
              ),
              for (final source in LogSource.values)
                GlassChip(
                  label: '${source.label}${counts[source] == null ? '' : ' ${counts[source]}'}',
                  selected: log.sourceFilter == source,
                  onTap: () => log.setFilter(source: source),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
