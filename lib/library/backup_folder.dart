import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../playback/documents.dart';
import 'library_backup.dart';

const backupFolderName = 'Tag Music 备份';
final _managedName = RegExp(
  r'^Tag Music-\d{4}-\d\d-\d\dT\d\d-\d\d-\d\dZ-(full|increment)-[0-9a-f-]{36}\.tagmusic$',
);

class BackupEntry {
  const BackupEntry(this.id, this.name, {required this.kind});

  final String id;
  final String name;
  final String kind;

  bool get isDirectory => kind == 'directory';
  bool get isBackup =>
      kind == 'file' && name.toLowerCase().endsWith('.tagmusic');
  bool get isManaged => isBackup && _managedName.hasMatch(name);
}

class BackupFolder {
  BackupFolder(this.documents, this.root, [String? directory])
    : id = directory ?? root;

  final DocumentAccess documents;
  final String root;
  final String id;

  static Future<String?> pick(
    DocumentAccess documents, {
    required bool write,
  }) => documents.android
      ? documents.channel.invokeMethod<String>('pickBackupDirectory', {
          'write': write,
        })
      : getDirectoryPath(confirmButtonText: write ? '使用此文件夹' : '打开备份文件夹');

  BackupFolder child(BackupEntry entry) =>
      BackupFolder(documents, root, entry.id);

  Future<T?> _call<T>(String method, [Map<String, Object>? arguments]) =>
      documents.channel.invokeMethod<T>(method, {
        'tree': root,
        'folder': id == root ? '' : id,
        ...?arguments,
      });

  Future<void> persistWriteAccess() async {
    if (documents.android) await _call<void>('persistBackupDirectory');
  }

  Future<List<BackupEntry>> list() async {
    if (documents.android) {
      final rows = (await _call<List<dynamic>>('backupFolderList'))!;
      return [
        for (final row in rows.cast<Map<Object?, Object?>>())
          BackupEntry(
            row['id'] as String,
            row['name'] as String,
            kind: row['kind'] as String,
          ),
      ];
    }
    return [
      await for (final entry in Directory(id).list(followLinks: false))
        BackupEntry(
          entry.path,
          p.basename(entry.path),
          kind: switch (entry) {
            File() => 'file',
            Directory() => 'directory',
            _ => 'other',
          },
        ),
    ];
  }

  Future<BackupFolder> createDirectory(String name) async {
    final childId = documents.android
        ? (await _call<String>('backupFolderCreate', {'name': name}))!
        : (await Directory(p.join(id, name)).create()).path;
    return BackupFolder(documents, root, childId);
  }

  Future<Uint8List> read(BackupEntry entry) async => documents.android
      ? (await _call<Uint8List>('backupFolderRead', {'document': entry.id}))!
      : readBackupFile(File(entry.id).openRead());

  Future<void> write(String name, Uint8List bytes) async {
    if (documents.android) {
      await _call<void>('backupFolderWrite', {'name': name, 'bytes': bytes});
    } else {
      final target = File(p.join(id, name));
      if (await FileSystemEntity.type(target.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('备份文件已存在', target.path);
      }
      await writeBackupFile(target, bytes);
    }
  }

  Future<void> remove(BackupEntry entry) async {
    if (!entry.isManaged) throw ArgumentError('只移除应用创建的备份副本');
    if (documents.android) {
      await _call<void>('backupFolderRemove', {'document': entry.id});
    } else {
      await File(entry.id).delete();
    }
  }

  Future<Uint8List> readSnapshot(String name) async {
    final byName = <String, BackupEntry>{};
    for (final entry in await list()) {
      if (!entry.isBackup) continue;
      if (byName.containsKey(entry.name)) {
        throw const FormatException('备份文件夹包含重名文件');
      }
      byName[entry.name] = entry;
    }

    final increments = <BackupEntry>[];
    final visited = <String>{};
    var entry = byName[name];
    while (entry != null && visited.add(entry.name)) {
      final bytes = await read(entry);
      final parent = await backupParent(bytes);
      if (parent == null) {
        var snapshot = bytes;
        for (final increment in increments.reversed) {
          snapshot = await applyBackupIncrement(
            snapshot,
            await read(increment),
          );
        }
        return snapshot;
      }
      increments.add(entry);
      entry = byName[parent];
    }
    throw const FormatException('备份链不完整，请保留完整备份和之前的增量记录。');
  }
}
