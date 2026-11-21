import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'filter_rule.dart';

typedef SyncRow = Map<String, dynamic>;
typedef SyncRows = Map<String, SyncRow>;

const syncSections = [
  'tracks',
  'tags',
  'songTags',
  'playlists',
  'filters',
  'settings',
];

class SyncData {
  SyncData([Map<String, SyncRows>? sections])
    : sections = {for (final name in syncSections) name: sections?[name] ?? {}};

  factory SyncData.decode(SyncRow wire) => SyncData({
    for (final name in syncSections)
      name: (wire[name] as SyncRow).cast<String, SyncRow>(),
  });

  final Map<String, SyncRows> sections;
  SyncRows operator [](String key) => sections[key]!;
}

String stableSyncId(String type, String value) =>
    '$type:${sha256.convert(utf8.encode(value))}';

String syncLink(String song, String tag) => jsonEncode([song, tag]);

String syncJson(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map<String, dynamic>) {
      final keys = item.keys.toList()..sort();
      return {for (final key in keys) key: normalize(item[key])};
    }
    if (item is List) return item.map(normalize).toList();
    return item;
  }

  return jsonEncode(normalize(value));
}

Map<String, Set<String>> syncTrackKeys(SyncRows tracks) => {
  for (final entry in tracks.entries)
    entry.key: {
      for (final path in entry.value['paths'] as List)
        jsonEncode([path, entry.value['size']]),
      if (entry.value['digest'] case final String digest) 'sha256:$digest',
    },
};

SyncData remapSyncData(
  SyncData data, {
  Map<String, String> songs = const {},
  Map<String, String> tags = const {},
  Map<String, String> playlists = const {},
}) {
  String tagId(String id) => tags[id] ?? id;
  String songId(String id) => songs[id] ?? id;
  SyncRow rewriteRule(SyncRow row) {
    final encoded = row['ruleJson'] as String?;
    if (encoded == null) return row;
    final rule = FilterRule.decode(encoded);
    return {
      ...row,
      'ruleJson': FilterRule(
        allTagIds: rule.allTagIds.map(tagId),
        anyTagIds: rule.anyTagIds.map(tagId),
        excludedTagIds: rule.excludedTagIds.map(tagId),
      ).encode(),
    };
  }

  final result = SyncData();
  for (final entry in data['tracks'].entries) {
    result['tracks'].putIfAbsent(songId(entry.key), () => entry.value);
  }
  for (final entry in data['tags'].entries) {
    final id = tagId(entry.key);
    result['tags'][id] = {...entry.value, 'id': id};
  }
  for (final entry in data['songTags'].values) {
    final song = songId(entry['songId'] as String);
    final tag = tagId(entry['tagId'] as String);
    result['songTags'][syncLink(song, tag)] = {'songId': song, 'tagId': tag};
  }
  for (final entry in data['playlists'].entries) {
    final id = playlists[entry.key] ?? entry.key;
    result['playlists'][id] = {
      ...rewriteRule(entry.value),
      'id': id,
      'members': (entry.value['members'] as List)
          .cast<String>()
          .map(songId)
          .toSet()
          .toList(),
    };
  }
  result['filters'].addAll(
    data['filters'].map((id, row) => MapEntry(id, rewriteRule(row))),
  );
  result['settings'].addAll(data['settings']);
  return result;
}

({SyncData data, Set<String> conflicts}) mergeSyncData(
  SyncData base,
  SyncData computer,
  SyncData phone, {
  required bool preferPhone,
}) {
  final conflicts = <String>{};
  final result = SyncData();
  T? merge<T>(T? before, T? here, T? there, String label) {
    final old = syncJson(before);
    final local = syncJson(here);
    final remote = syncJson(there);
    if (local == remote || remote == old) return here;
    if (local == old) return there;
    conflicts.add(label);
    return preferPhone ? there : here;
  }

  SyncRow? mergePlaylist(SyncRow? before, SyncRow? here, SyncRow? there) {
    final name = (here ?? there ?? before)!['name'];
    final label = '歌单「$name」';
    if (here == null || there == null || here['kind'] != there['kind']) {
      return merge(before, here, there, label);
    }
    final local = {...here};
    final remote = {...there};
    final old = {...?before};
    final localOrder = (local.remove('members') as List).cast<String>();
    final remoteOrder = (remote.remove('members') as List).cast<String>();
    final oldOrder = (old.remove('members') as List? ?? []).cast<String>();
    final attrs = <String, dynamic>{
      for (final key in {...local.keys, ...remote.keys})
        key: merge(old[key], local[key], remote[key], label),
    };
    final inOld = oldOrder.toSet();
    final inLocal = localOrder.toSet();
    final inRemote = remoteOrder.toSet();
    final keep = {
      for (final id in {...inLocal, ...inRemote})
        if (!inOld.contains(id) ||
            (inLocal.contains(id) && inRemote.contains(id)))
          id,
    };
    final shared = inLocal.intersection(inRemote).intersection(keep);
    final common = oldOrder.where(shared.contains).toList();
    final anchors = common.toSet();
    final chosen = merge(
      common,
      localOrder.where(anchors.contains).toList(),
      remoteOrder.where(anchors.contains).toList(),
      '$label的顺序',
    )!;
    final combined = chosen.toList();
    void insertMissing(List<String> source) {
      String? previous;
      for (final id in source.where(keep.contains)) {
        if (!combined.contains(id)) {
          final next = previous == null ? 0 : combined.indexOf(previous) + 1;
          combined.insert(next, id);
        }
        previous = id;
      }
    }

    insertMissing(preferPhone ? localOrder : remoteOrder);
    insertMissing(preferPhone ? remoteOrder : localOrder);
    return {...attrs, 'members': combined};
  }

  final labels = {
    'tags': '标签',
    'songTags': '歌曲标签',
    'filters': '筛选规则',
    'settings': '设置',
  };
  for (final section in syncSections) {
    for (final id in {
      ...base[section].keys,
      ...computer[section].keys,
      ...phone[section].keys,
    }) {
      final old = base[section][id];
      final left = computer[section][id];
      final right = phone[section][id];
      final SyncRow? row;
      if (section == 'tracks') {
        row = left ?? right ?? old;
      } else if (section == 'playlists') {
        row = mergePlaylist(old, left, right);
      } else {
        final name =
            (left ?? right ?? old)?['name'] ??
            (section == 'settings' ? id : null);
        row = merge(
          old,
          left,
          right,
          name == null ? labels[section]! : '${labels[section]}「$name」',
        );
      }
      if (row != null) result[section][id] = row;
    }
  }

  // A deletion also removes references on the other device, including smart
  // rules that may have been edited concurrently.
  final liveTags = result['tags'].keys.toSet();
  result['songTags'].removeWhere((_, row) => !liveTags.contains(row['tagId']));
  for (final section in ['playlists', 'filters']) {
    result[section].updateAll((_, row) {
      if (row['ruleJson'] case final String encoded) {
        var rule = FilterRule.decode(encoded);
        for (final removed in rule.referencedIds.difference(liveTags)) {
          rule = rule.without(removed);
        }
        return {...row, 'ruleJson': rule.encode()};
      }
      return row;
    });
  }
  for (final section in ['tags', 'playlists']) {
    final names = <String>{};
    final ordered = result[section].keys.toList()..sort();
    for (final id in ordered) {
      final row = result[section][id]!;
      final name = row['name'] as String;
      var display = name;
      var suffix = 2;
      while (!names.add(display.toLowerCase())) {
        display = '$name（$suffix）';
        suffix++;
      }
      if (display != name) {
        result[section][id] = {
          ...row,
          'name': display,
          'nameKey': display.toLowerCase(),
        };
      }
    }
  }
  return (data: result, conflicts: conflicts);
}
