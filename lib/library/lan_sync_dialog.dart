import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/compact_dialog.dart';
import '../core/settings.dart';
import 'lan_sync_connection.dart';
import 'lan_sync_merge.dart';
import 'lan_sync_service.dart';
import 'library_controller.dart';

Future<void> showLanSync(BuildContext context, LibraryController library) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LanSyncDialog(library),
    );

class _LanSyncDialog extends ConsumerStatefulWidget {
  const _LanSyncDialog(this.library);

  final LibraryController library;

  @override
  ConsumerState<_LanSyncDialog> createState() => _LanSyncDialogState();
}

class _LanSyncDialogState extends ConsumerState<_LanSyncDialog> {
  final _code = TextEditingController();
  late final _service = LanSyncService(
    widget.library,
    _settings,
    _applySettings,
  );
  LanSyncReceiver? _receiver;
  bool _busy = false;
  String? _status;
  bool get _phone => widget.library.documents.android;

  SyncRows _settings() => {
    '主题模式': {'value': ref.read(themeProvider).name},
    '主题颜色': {'value': ref.read(themeColorProvider).name},
  };

  Future<void> _applySettings(SyncRows values) async {
    final mode = decodeTheme(values['主题模式']?['value'] as String?);
    final color = ThemeColor.decode(values['主题颜色']?['value'] as String?);
    if (ref.read(themeProvider) != mode) {
      await ref.read(themeProvider.notifier).select(mode);
    }
    if (ref.read(themeColorProvider) != color) {
      await ref.read(themeColorProvider.notifier).select(color);
    }
  }

  @override
  void initState() {
    super.initState();
    if (_phone) {
      _run(() async {
        final saved = await _service.store.read('lan-endpoint');
        if (mounted && saved != null) _code.text = saved;
      });
    }
  }

  @override
  void dispose() {
    _receiver?.close();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      _status = error.message;
    } on StateError catch (error) {
      _status = error.message.toString();
    } on SocketException {
      _status = _phone
          ? '无法连接电脑。请确认在同一局域网、电脑仍开着同步窗口，并使用该网络对应的连接码。'
          : '无法开启局域网同步。请检查电脑网络，或关闭其他正在等待同步的窗口。';
    } catch (_) {
      _status = '同步未完成。请核对连接码和两端同步状态后重试。';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _completed(int pending) =>
      pending == 0 ? '同步完成。' : '同步完成。$pending 首歌曲尚未在本机匹配，已保留标签和歌单关系。';

  Future<void> _start() => _run(() async {
    final receiver = await _service.listen(_resolve, (count) {
      if (mounted) setState(() => _status = _completed(count));
    });
    if (!mounted) {
      receiver.close();
      return;
    }
    _receiver = receiver;
    _status = '等待手机连接。';
  });

  Future<void> _sync() => _run(() async {
    _status = _completed(await _service.connect(_code.text));
  });

  Future<bool?> _resolve(Set<String> conflicts) => showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => CompactAlertDialog(
      scrollable: true,
      title: const Text('两端修改了同一内容'),
      content: Text('以下冲突需选择以哪一端为准。其他可以合并的改动都会保留。\n\n${conflicts.join('\n')}'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消同步'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('冲突以电脑为准'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('冲突以手机为准'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.library,
    builder: (context, _) {
      final busy = _busy || widget.library.syncing;
      final receiver = _receiver;
      return PopScope(
        canPop: !busy,
        child: CompactAlertDialog(
          scrollable: true,
          title: const Text('局域网同步'),
          content: SizedBox(
            width: 410,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('两端接入同一 Wi‑Fi。同步标签、收藏、歌单、筛选和主题设置。'),
                const SizedBox(height: 12),
                if (_phone)
                  TextField(
                    controller: _code,
                    enabled: !busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: '电脑上显示的连接码',
                      border: OutlineInputBorder(),
                    ),
                  )
                else if (receiver == null)
                  const Text('点击后，电脑会显示连接码。Windows 若询问网络访问权限，请选择允许专用网络。')
                else
                  for (final endpoint in receiver.endpoints)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(endpoint.address.address),
                      subtitle: SelectableText(endpoint.code),
                      trailing: IconButton(
                        tooltip: '复制连接码',
                        icon: const Icon(Icons.copy_outlined),
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: endpoint.code),
                        ),
                      ),
                    ),
                if (busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const Text('正在同步。若有冲突，请在电脑上确认。'),
                ],
                if (_status case final status?) ...[
                  const SizedBox(height: 8),
                  Text(status),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
            if (_phone || receiver == null)
              FilledButton(
                onPressed: busy || widget.library.directoryBusy
                    ? null
                    : (_phone ? _sync : _start),
                child: Text(_phone ? '立即同步' : '等待手机连接'),
              ),
          ],
        ),
      );
    },
  );
}
