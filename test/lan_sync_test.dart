import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/library/lan_sync_merge.dart';
import 'package:tag_music/library/portable_paths.dart';

void main() {
  test('directory names and portable song paths match across devices', () {
    const windows = r'D:\音乐\华语';
    const android =
        'content://com.android.externalstorage.documents/tree/primary%3AMusic%2F%E5%8D%8E%E8%AF%AD';
    expect(portableFolderName(windows), portableFolderName(android));
    expect(
      portableRelativePath(windows, r'专辑\晴天.FLAC'),
      portableRelativePath(android, '专辑/晴天.flac'),
    );
    expect(
      uniqueMusicMatches(
        {
          'phone': {'path', 'sha256:a'},
        },
        {
          'pc': {'path', 'sha256:b'},
        },
      ),
      isEmpty,
    );
    expect(
      uniqueMusicMatches(
        {
          'phone': {'path'},
        },
        {
          'pc1': {'path'},
          'pc2': {'path'},
        },
      ),
      isEmpty,
    );
  });

  SyncData data(
    List<String> members, {
    bool tag = true,
    bool assigned = false,
  }) => SyncData({
    'tags': {
      if (tag) 'tag': {'id': 'tag', 'name': '通勤', 'nameKey': '通勤'},
    },
    'songTags': {
      if (assigned) syncLink('a', 'tag'): {'songId': 'a', 'tagId': 'tag'},
    },
    'playlists': {
      'list': {
        'id': 'list',
        'name': '收藏',
        'nameKey': '收藏',
        'kind': 'regular',
        'members': members,
      },
    },
  });

  test('two playlist edits merge and a deleted tag is not revived', () {
    final merged = mergeSyncData(
      data(['a', 'b']),
      data(['a', 'b', 'c'], tag: false),
      data(['b', 'd'], assigned: true),
      preferPhone: false,
    );
    expect(merged.conflicts, isEmpty);
    expect(
      merged.data['playlists']['list']!['members'],
      unorderedEquals(['b', 'c', 'd']),
    );
    expect(merged.data['tags'], isEmpty);
    expect(merged.data['songTags'], isEmpty);
  });

  test(
    'concurrent reorder asks which side to keep and retains other additions',
    () {
      final base = data(['a', 'b', 'c']);
      final computer = data(['b', 'a', 'c', 'd']);
      final phone = data(['a', 'c', 'b']);
      final merged = mergeSyncData(base, computer, phone, preferPhone: true);
      expect(merged.conflicts, {'歌单「收藏」的顺序'});
      expect(merged.data['playlists']['list']!['members'], [
        'a',
        'c',
        'd',
        'b',
      ]);
    },
  );
}
