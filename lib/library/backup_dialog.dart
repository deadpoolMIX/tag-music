import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/compact_dialog.dart';
import 'library_backup.dart';
import 'library_controller.dart';

Future<void> showLibraryBackup(
  BuildContext context,
  LibraryController library, {
  Future<void> Function()? clearPlayback,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _BackupDialog(library: library, clearPlayback: clearPlayback),
);

class _BackupDialog extends StatefulWidget {
  const _BackupDialog({required this.library, this.clearPlayback});

  final LibraryController library;
  final Future<void> Function()? clearPlayback;

  @override
  State<_BackupDialog> createState() => _BackupDialogState();
}

class _BackupDialogState extends State<_BackupDialog> {
  bool _busy = false;
  bool _local = false;
  String? _status;
  LibraryBackup? _preview;

  Future<void> _run(Future<void> Function() action, String failure) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action();
    } on FormatException catch (error) {
      _status = error.message;
    } on PlatformException catch (error) {
      _status = error.message ?? failure;
    } catch (error, stack) {
      debugPrint('$failure $error\n$stack');
      _status = failure;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final library = widget.library;
    final bytes = await LibraryBackup.export(library.db);
    final date = DateTime.now().toLocal().toIso8601String().substring(0, 19);
    final name = 'Tag Music-${date.replaceAll(':', '-')}.tagmusic';
    if (library.documents.android) {
      if (await library.documents.channel.invokeMethod<bool>(
            'exportLibraryBackup',
            {'name': name, 'bytes': bytes},
          ) !=
          true) {
        return;
      }
    } else {
      final target = await getSaveLocation(
        suggestedName: name,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Tag Music 备份', extensions: ['tagmusic']),
        ],
      );
      if (target == null) return;
      await writeBackupFile(File(target.path), bytes);
    }
    _status = '备份已导出。';
  }, '导出失败，请检查保存位置和可用空间。');

  Future<Uint8List?> _pick() async {
    final documents = widget.library.documents;
    if (documents.android) {
      return documents.channel.invokeMethod<Uint8List>('importLibraryBackup');
    }
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Tag Music 备份', extensions: ['tagmusic']),
      ],
    );
    return file == null ? null : readBackupFile(file.openRead());
  }

  Future<void> _read({required bool local}) => _run(() async {
    Uint8List? bytes;
    if (local) {
      final file = await recoveryBackupFile();
      if (!await file.exists()) {
        _status = '还没有恢复前的本机备份。';
        return;
      }
      bytes = await readBackupFile(file.openRead());
    } else {
      bytes = await _pick();
    }
    if (bytes == null) return;
    _preview = await LibraryBackup.decode(bytes);
    _local = local;
  }, '无法读取备份，请检查文件是否可以访问。');

  Future<void> _restore(LibraryBackup backup) => _run(() async {
    final recoveryFile = await recoveryBackupFile();
    final reloaded = await widget.library.restoreBackup(
      backup,
      recoveryFile,
      trustedLocations: _local,
    );
    _preview = null;
    _status = reloaded ? '已恢复管理数据，并保存了恢复前的本机备份。' : '已恢复管理数据。请重新打开应用以加载恢复后的曲库。';
    try {
      await widget.clearPlayback?.call();
    } catch (error, stack) {
      debugPrint('清理播放队列失败 $error\n$stack');
      _status = '管理数据已恢复。播放队列未能清空，请重新打开应用。';
    }
  }, '恢复失败。请检查备份内容和可用空间。');

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return PopScope(
      canPop: !_busy,
      child: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) => CompactAlertDialog(
          scrollable: true,
          title: Text(preview == null ? '备份与恢复' : '确认恢复备份'),
          content: SizedBox(
            width: 380,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (preview == null) ...[
                  const Text('备份包含曲库记录、标签、歌单和筛选规则，不包含音乐文件。'),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.save_alt),
                    title: const Text('导出备份'),
                    enabled: !_busy,
                    onTap: _busy ? null : _export,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('从文件恢复'),
                    enabled: !_busy,
                    onTap: _busy ? null : () => _read(local: false),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: const Text('恢复到上次恢复前'),
                    enabled: !_busy,
                    onTap: _busy ? null : () => _read(local: true),
                  ),
                ] else ...[
                  Text(
                    '${preview.songs.length} 首歌曲记录 · ${preview.roots.length} 个目录\n'
                    '${preview.tags.length} 个标签 · ${preview.playlists.length} 个歌单',
                  ),
                  const SizedBox(height: 8),
                  const Text('恢复会替换当前曲库、标签、歌单和筛选，并清空播放队列。应用会先保存当前管理数据。'),
                  if (!_local) const Text('当前曲库中没有的音乐位置需要重新定位。'),
                ],
                if (_busy) const LinearProgressIndicator(),
                if (_status case final status?) Text(status),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (preview == null) {
                        Navigator.pop(context);
                      } else {
                        setState(() {
                          _preview = null;
                          _status = null;
                        });
                      }
                    },
              child: Text(preview == null ? '关闭' : '返回'),
            ),
            if (preview != null)
              FilledButton(
                onPressed: _busy || widget.library.directoryBusy
                    ? null
                    : () => _restore(preview),
                child: const Text('恢复并替换'),
              ),
          ],
        ),
      ),
    );
  }
}
