import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'lan_sync_connection.dart';
import 'lan_sync_merge.dart';
import 'lan_sync_store.dart';
import 'library_controller.dart';
import 'portable_paths.dart';

const _version = 1;

class LanSyncService {
  LanSyncService(this.library, this.readSettings, this.writeSettings)
    : store = LanSyncStore(library.db);

  final LibraryController library;
  final SyncRows Function() readSettings;
  final Future<void> Function(SyncRows) writeSettings;
  final LanSyncStore store;

  Future<LanSyncReceiver> listen(
    Future<bool?> Function(Set<String>) resolve,
    void Function(int pending) received,
  ) async {
    final key = await store.read('lan-key') ?? LanEndpoint.newKey();
    await store.write('lan-key', key);
    return LanSyncReceiver.open(base64Url.decode(key), (request) async {
      try {
        return await library.syncLibrary(
          () => _accept(request, resolve, received),
        );
      } on FormatException catch (error) {
        return {'error': error.message};
      } on StateError catch (error) {
        return {'error': error.message};
      } catch (_) {
        return {'error': '电脑同步失败，请重新打开同步窗口再试。'};
      }
    });
  }

  Future<SyncRow> _accept(
    SyncRow request,
    Future<bool?> Function(Set<String>) resolve,
    void Function(int pending) received,
  ) async {
    if (request['version'] != _version) {
      throw const FormatException('手机和电脑的同步版本不一致。');
    }
    final device = request['device'] as String;
    if (device.length != 36) throw const FormatException('设备标识无效。');
    final peer = 'phone:$device';
    await store.applyPendingSettings(writeSettings);
    final before = await store.snapshot(peer, readSettings());
    final incoming = SyncData.decode(request['data'] as SyncRow);
    final base = SyncData.decode(request['base'] as SyncRow);
    final here = before.current;

    final trackIds =
        uniqueMusicMatches(
          syncTrackKeys(incoming['tracks']),
          syncTrackKeys(here['tracks']),
        )..removeWhere(
          (from, to) =>
              from == to ||
              here['tracks'].containsKey(from) ||
              incoming['tracks'].containsKey(to) ||
              base['tracks'].containsKey(from),
        );
    Map<String, String> equivalentNames(String section, {bool kind = false}) {
      String key(SyncRow row) => '${kind ? row['kind'] : ''}:${row['nameKey']}';
      final exact = {
        for (final entry in here[section].entries) key(entry.value): entry.key,
      };
      return {
        for (final entry in incoming[section].entries)
          if (!base[section].containsKey(entry.key) &&
              !here[section].containsKey(entry.key))
            if (exact[key(entry.value)] case final id?
                when !incoming[section].containsKey(id))
              entry.key: id,
      };
    }

    final there = remapSyncData(
      incoming,
      songs: trackIds,
      tags: equivalentNames('tags'),
      playlists: equivalentNames('playlists', kind: true),
    );
    var merged = mergeSyncData(base, here, there, preferPhone: false);
    if (merged.conflicts.isNotEmpty) {
      final choice = await resolve(merged.conflicts);
      if (choice == null) return {'error': '本次同步已在电脑上取消。'};
      if (choice) merged = mergeSyncData(base, here, there, preferPhone: true);
    }
    final pending = await store.apply(
      peer: peer,
      before: before,
      after: merged.data,
      settings: readSettings(),
    );
    await store.applyPendingSettings(writeSettings);
    received(pending);
    return {
      'version': _version,
      'data': merged.data.sections,
      'tracks': trackIds,
    };
  }

  Future<int> connect(String code) => library.syncLibrary(() async {
    final endpoint = LanEndpoint.decode(code);
    final peer = endpoint.peer;
    await store.applyPendingSettings(writeSettings);
    final device = await store.read('lan-device') ?? const Uuid().v4();
    await store.write('lan-device', device);
    final before = await store.snapshot(peer, readSettings());
    final reply = await endpoint.exchange({
      'version': _version,
      'device': device,
      'data': before.current.sections,
      'base': before.base.sections,
    });
    if (reply['error'] case final String error) throw FormatException(error);
    if (reply['version'] != _version) {
      throw const FormatException('手机和电脑的同步版本不一致。');
    }
    final after = SyncData.decode(reply['data'] as SyncRow);
    final tracks = (reply['tracks'] as SyncRow).cast<String, String>();
    final count = await store.apply(
      peer: peer,
      before: before,
      after: after,
      settings: readSettings(),
      remapped: tracks,
    );
    await store.applyPendingSettings(writeSettings);
    await store.write('lan-endpoint', endpoint.code);
    return count;
  });
}
