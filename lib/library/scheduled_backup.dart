import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../playback/documents.dart';
import 'backup_folder.dart';
import 'database.dart';
import 'library_backup.dart';

class ScheduledLibraryBackup extends ChangeNotifier {
  ScheduledLibraryBackup(
    this.db,
    this.documents, {
    Future<File> Function()? stateFile,
    DateTime Function()? clock,
  }) : _stateFile = stateFile ?? _defaultStateFile,
       _clock = clock ?? DateTime.now;

  final LibraryDatabase db;
  final DocumentAccess documents;
  final Future<File> Function() _stateFile;
  final DateTime Function() _clock;
  static const interval = Duration(days: 7);

  AppLifecycleListener? _lifecycle;
  Timer? _timer;
  Future<void>? _task;
  bool _closed = false;
  DateTime? lastBackup;
  String? problem;

  static Future<File> _defaultStateFile() async => File(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'backup-schedule.json',
    ),
  );

  void start() {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => check());
    unawaited(check());
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _lifecycle?.dispose();
    try {
      await _task;
    } catch (_) {
      // A failed manual backup is already reported by its caller.
    }
    dispose();
  }

  Future<void> _run(Future<void> Function() action) =>
      _task = Future<void>.sync(action).whenComplete(() => _task = null);

  Future<_BackupState?> _load() async {
    final file = await _stateFile();
    if (!await file.exists()) return null;
    final state = _BackupState.decode(await file.readAsString());
    lastBackup = state.completedAt;
    return state;
  }

  Future<void> manualBackup(String root) async {
    while (true) {
      if (_closed) throw StateError('曲库已关闭');
      final pending = _task;
      if (pending == null) break;
      try {
        await pending;
      } catch (_) {
        // A new manual backup can replace a failed attempt.
      }
    }
    await _run(() async {
      _BackupState? previous;
      try {
        previous = await _load();
      } on FormatException {
        // A successful manual backup replaces an unreadable schedule.
      } on TypeError {
        // Older or malformed settings can also be replaced manually.
      }
      await _save(root, previous?.root == root ? previous : null, manual: true);
    });
  }

  Future<void> check() async {
    if (_closed || _task != null) return;
    await _run(() async {
      try {
        final previous = await _load();
        if (previous != null &&
            _clock().difference(previous.completedAt) >= interval) {
          await _save(previous.root, previous, manual: false);
        } else if (previous != null) {
          notifyListeners();
        }
      } catch (error, stack) {
        debugPrint('自动备份失败：$error\n$stack');
        problem = '自动备份暂未完成。请检查备份文件夹和授权，或重新手动备份。';
        notifyListeners();
      }
    });
  }

  Future<void> _save(
    String root,
    _BackupState? previous, {
    required bool manual,
  }) async {
    final selected = BackupFolder(documents, root);
    final top = await selected.list();
    final previousDirectory = previous?.directory;
    final existing = top
        .where((entry) => entry.isDirectory && entry.id == previousDirectory)
        .firstOrNull;
    final source = existing == null ? selected : selected.child(existing);
    final entries = existing == null ? top : await source.list();
    final snapshot = await LibraryBackup.export(db);
    final bytes = manual
        ? snapshot
        : await encodeBackupIncrement(
            previous!.head,
            await source.readSnapshot(previous.head, entries: entries),
            snapshot,
          );

    var destination = source;
    final copied = <BackupEntry>[];
    if (entries.any((entry) => !entry.isBackup)) {
      // A pre-existing item with the same name may belong to the user.
      final occupied = top.map((entry) => entry.name.toLowerCase()).toSet();
      var name = backupFolderName;
      for (var suffix = 2; occupied.contains(name.toLowerCase()); suffix++) {
        name = '$backupFolderName $suffix';
      }
      destination = await selected.createDirectory(name);
      for (final entry in entries.where((entry) => entry.isManaged)) {
        await _writeVerified(destination, entry.name, await source.read(entry));
        copied.add(entry);
      }
    }

    final stamp =
        '${_clock().toUtc().toIso8601String().substring(0, 19).replaceAll(':', '-')}Z';
    final kind = manual ? 'full' : 'increment';
    final name = 'Tag Music-$stamp-$kind-${const Uuid().v4()}.tagmusic';
    await _writeVerified(destination, name, bytes);
    if (!manual &&
        copied.isNotEmpty &&
        !listEquals(snapshot, await destination.readSnapshot(name))) {
      throw const FormatException('迁移后的备份校验失败');
    }
    if (manual) await selected.persistWriteAccess();
    final completedAt = _clock().toUtc();
    final state = _BackupState(root, destination.id, name, completedAt);
    await writeBackupFile(await _stateFile(), state.encode());
    lastBackup = completedAt;
    problem = null;

    // Leave originals in place until the new folder and schedule are durable.
    if (copied.isNotEmpty) {
      try {
        final files = {
          for (final entry in await destination.list()) entry.name: entry,
        };
        for (final entry in copied) {
          final copy = files[entry.name]!;
          if (listEquals(
            await source.read(entry),
            await destination.read(copy),
          )) {
            await source.remove(entry);
          }
        }
      } catch (error, stack) {
        debugPrint('备份已保存，旧位置清理未完成：$error\n$stack');
        problem = '备份已保存，旧文件夹中保留了备份副本。';
      }
    }
    notifyListeners();
  }

  Future<void> _writeVerified(
    BackupFolder folder,
    String name,
    Uint8List bytes,
  ) async {
    await folder.write(name, bytes);
    final entry = (await folder.list()).singleWhere(
      (entry) => entry.isBackup && entry.name == name,
    );
    if (!listEquals(bytes, await folder.read(entry))) {
      throw const FormatException('写入后的备份校验失败');
    }
  }
}

class _BackupState {
  const _BackupState(this.root, this.directory, this.head, this.completedAt);

  final String root;
  final String directory;
  final String head;
  final DateTime completedAt;

  factory _BackupState.decode(String text) {
    final data = jsonDecode(text) as Map<String, dynamic>;
    return _BackupState(
      data['root'] as String,
      data['directory'] as String,
      data['head'] as String,
      DateTime.parse(data['completedAt'] as String),
    );
  }

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'root': root,
        'directory': directory,
        'head': head,
        'completedAt': completedAt.toIso8601String(),
      }),
    ),
  );
}
