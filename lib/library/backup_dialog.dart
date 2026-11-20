import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/compact_dialog.dart';
import 'backup_folder.dart';
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
    final root = await BackupFolder.pick(library.documents, write: true);
    if (root == null) return;
    await library.scheduledBackup.manualBackup(root);
    _status = '完整备份已保存，之后每 7 天自动保存一份完整备份。';
  }, '导出失败，请检查保存位置和可用空间。');

  Future<void> _readFolder() => _run(() async {
    final documents = widget.library.documents;
    final root = await BackupFolder.pick(documents, write: false);
    if (root == null) return;
    final folder = BackupFolder(documents, root);
    final choices = <({BackupFolder folder, BackupEntry file})>[];
    final entries = await folder.list();
    for (final entry in entries) {
      if (entry.isBackup) {
        choices.add((folder: folder, file: entry));
      } else if (entry.isDirectory && entry.name.startsWith(backupFolderName)) {
        final child = folder.child(entry);
        for (final file in await child.list()) {
          if (file.isBackup) choices.add((folder: child, file: file));
        }
      }
    }
    if (choices.isEmpty) {
      _status = '所选文件夹没有备份文件。';
      return;
    }
    choices.sort((a, b) => b.file.name.compareTo(a.file.name));
    if (!mounted) return;
    final index = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择恢复时间'),
        children: [
          for (final (index, choice) in choices.indexed)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, index),
              child: Text(choice.file.name),
            ),
        ],
      ),
    );
    if (index == null) return;
    final choice = choices[index];
    _preview = await LibraryBackup.decode(
      await choice.folder.readSnapshot(choice.file.name),
    );
    _local = false;
  }, '无法读取备份文件夹，请检查授权和备份记录。');

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
    final backup = widget.library.scheduledBackup;
    return PopScope(
      canPop: !_busy,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.library, backup]),
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
                  Text(
                    backup.lastBackup == null
                        ? '手动备份一次后，每 7 天自动保存一份完整备份。'
                        : '自动备份已开启，应用运行时每 7 天保存一份完整备份。',
                  ),
                  if (backup.problem case final problem?) Text(problem),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.save_alt),
                    title: const Text('手动备份'),
                    subtitle: const Text('选择文件夹并保存完整备份'),
                    enabled: !_busy,
                    onTap: _busy ? null : _export,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.folder_open),
                    title: const Text('从备份文件夹恢复'),
                    enabled: !_busy,
                    onTap: _busy ? null : _readFolder,
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
                  const Text(
                    '恢复会替换当前曲库、标签、歌单、筛选和备份中有记录的播放次数，并清空播放队列。应用会先保存当前管理数据。',
                  ),
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
