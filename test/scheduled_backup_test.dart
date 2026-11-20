import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tag_music/library/backup_folder.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_backup.dart';
import 'package:tag_music/library/scheduled_backup.dart';
import 'package:tag_music/library/tag_repository.dart';
import 'package:tag_music/playback/documents.dart';

void main() {
  late Directory temp;
  late Directory destination;
  late File settings;
  late DateTime now;
  late LibraryDatabase db;
  late TagRepository tags;
  late DocumentAccess documents;
  late ScheduledLibraryBackup service;

  ScheduledLibraryBackup createService() => ScheduledLibraryBackup(
    db,
    documents,
    stateFile: () async => settings,
    clock: () => now,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tag-music-backup-');
    destination = await Directory(p.join(temp.path, 'exports')).create();
    settings = File(p.join(temp.path, 'schedule.json'));
    now = DateTime.utc(2026, 11, 20);
    db = LibraryDatabase(NativeDatabase.memory());
    tags = TagRepository(db);
    documents = DocumentAccess(android: false);
    service = createService();
  });

  tearDown(() async {
    await service.close();
    await db.close();
    await temp.delete(recursive: true);
  });

  test(
    'requires a successful manual backup, then saves each week of changes',
    () async {
      await expectLater(
        service.manualBackup(p.join(temp.path, 'missing')),
        throwsA(isA<FileSystemException>()),
      );
      await service.check();
      expect(await settings.exists(), isFalse);
      expect(await destination.list().toList(), isEmpty);

      await tags.create('更名');
      await tags.create('删除');
      await tags.create('保留');
      final original = {
        for (final tag in (await tags.load()).tags) tag.name: tag.id,
      };
      await service.manualBackup(destination.path);
      final root = BackupFolder(documents, destination.path);
      final first = (await root.list()).single;
      final originalBytes = await root.read(first);
      expect(await backupParent(originalBytes), isNull);

      await tags.rename(original['更名']!, '新名称');
      await tags.delete(original['删除']!);
      await tags.create('新增');
      now = now.add(const Duration(days: 6, hours: 23));
      await service.check();
      expect(await root.list(), hasLength(1));
      now = now.add(const Duration(hours: 1));
      await Future.wait([service.check(), service.check()]);
      final firstIncrement = (await root.list()).singleWhere(
        (entry) => entry.name != first.name,
      );
      final increment = await root.read(firstIncrement);
      expect(await backupParent(increment), first.name);
      expect(utf8.decode(increment), isNot(contains('保留')));
      expect(
        await root.readSnapshot(firstIncrement.name),
        await LibraryBackup.export(db),
      );

      // Base and both increments must be available together after relocation.
      final note = await File(p.join(destination.path, '外部文件.txt'))
          .writeAsString('保留我');
      await service.close();
      service = createService();
      now = now.add(const Duration(days: 7));
      await tags.rename(original['保留']!, '第二周');
      await service.check();
      expect(service.problem, isNull);
      final top = await root.list();
      expect(top, hasLength(2));
      final dedicated = root.child(
        top.singleWhere((entry) => entry.isDirectory),
      );
      final files = await dedicated.list();
      expect(files, hasLength(3));
      expect(await note.readAsString(), '保留我');
      final second = files.singleWhere(
        (entry) => !{first.name, firstIncrement.name}.contains(entry.name),
      );
      expect(
        await backupParent(await dedicated.read(second)),
        firstIncrement.name,
      );
      expect(
        await dedicated.readSnapshot(second.name),
        await LibraryBackup.export(db),
      );
      expect(await dedicated.readSnapshot(first.name), originalBytes);

      await dedicated.remove(
        files.singleWhere((entry) => entry.name == firstIncrement.name),
      );
      await expectLater(
        dedicated.readSnapshot(second.name),
        throwsFormatException,
      );
    },
  );

  test(
    'mixed destinations get a dedicated folder without touching existing items',
    () async {
      final existing = await Directory(
        p.join(destination.path, backupFolderName),
      ).create();
      final note = await File(p.join(existing.path, '说明.txt'))
          .writeAsString('用户文件');
      await service.manualBackup(destination.path);
      final root = BackupFolder(documents, destination.path);
      final dedicated = root.child(
        (await root.list()).singleWhere(
          (entry) => entry.name == '$backupFolderName 2',
        ),
      );
      final full = (await dedicated.list()).single;
      expect(await backupParent(await dedicated.read(full)), isNull);
      expect(await note.readAsString(), '用户文件');
    },
  );
}
