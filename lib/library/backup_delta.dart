part of 'library_backup.dart';

const _incrementFormat = 'tag-music-library-increment';
const _primaryKeys = {
  'songs': ['id'],
  'roots': ['location'],
  'locations': ['songId', 'root'],
  'tags': ['id'],
  'songTags': ['songId', 'tagId'],
  'filters': ['id'],
  'playlists': ['id'],
  'playlistSongs': ['playlistId', 'songId'],
};

String _rowKey(String table, Map<String, dynamic> row) =>
    jsonEncode(_primaryKeys[table]!.map((field) => row[field]).toList());

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

Uint8List _encodePackage(String format, Map<String, dynamic> data) {
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format': format,
        'version': _version,
        'checksum': _hash(utf8.encode(jsonEncode(data))),
        'data': data,
      }),
    ),
  );
  if (bytes.length > backupByteLimit) {
    throw const FormatException('备份超过 64 MiB');
  }
  return bytes;
}

({String format, Map<String, dynamic> data}) _readPackage(Uint8List bytes) {
  if (bytes.length > backupByteLimit) {
    throw const FormatException('备份超过 64 MiB');
  }
  final package = jsonDecode(utf8.decode(bytes));
  if (package is! Map<String, dynamic> || package['format'] is! String) {
    throw const FormatException('请选择 Tag Music 备份文件');
  }
  if (package['version'] is! int || package['version'] != _version) {
    throw const FormatException('备份版本不受支持');
  }
  final data = package['data'];
  if (data is! Map<String, dynamic> ||
      _hash(utf8.encode(jsonEncode(data))) != package['checksum']) {
    throw const FormatException('备份校验失败，文件可能损坏');
  }
  return (format: package['format'] as String, data: data);
}

Map<String, Map<String, dynamic>> _keyedRows(
  String table,
  Map<String, dynamic> snapshot,
) => {
  for (final row in (snapshot[table] as List).cast<Map<String, dynamic>>())
    _rowKey(table, row): row,
};

Future<Uint8List> encodeBackupIncrement(
  String parent,
  Uint8List before,
  Uint8List after,
) => Isolate.run(() {
  final previous = _readPackage(before).data;
  final current = _readPackage(after).data;
  final changes = <String, dynamic>{};
  for (final table in _primaryKeys.keys) {
    final old = _keyedRows(table, previous);
    final next = _keyedRows(table, current);
    final removed = old.keys.where((key) => !next.containsKey(key)).toList();
    final changed = [
      for (final entry in next.entries)
        if (jsonEncode(old[entry.key]) != jsonEncode(entry.value)) entry.value,
    ];
    if (removed.isNotEmpty || changed.isNotEmpty) {
      changes[table] = {'removed': removed, 'changed': changed};
    }
  }
  return _encodePackage(_incrementFormat, {
    'parent': parent,
    'base': _hash(before),
    'result': _hash(after),
    'changes': changes,
  });
});

Future<String?> backupParent(Uint8List bytes) => Isolate.run(() {
  final package = _readPackage(bytes);
  if (package.format == _format) return null;
  final parent = package.data['parent'];
  if (package.format != _incrementFormat || parent is! String) {
    throw const FormatException('备份的增量记录无效');
  }
  return parent;
});

Future<Uint8List> applyBackupIncrement(Uint8List before, Uint8List delta) =>
    Isolate.run(() {
      try {
        final base = _readPackage(before);
        final increment = _readPackage(delta);
        if (base.format != _format ||
            increment.format != _incrementFormat ||
            increment.data['base'] != _hash(before)) {
          throw const FormatException('增量备份与上一份记录不匹配');
        }
        final changes = increment.data['changes'] as Map<String, dynamic>;
        final result = <String, dynamic>{};
        for (final table in _primaryKeys.keys) {
          final rows = _keyedRows(table, base.data);
          if (changes[table] case final Map<String, dynamic> change) {
            for (final key in (change['removed'] as List).cast<String>()) {
              rows.remove(key);
            }
            for (final row
                in (change['changed'] as List).cast<Map<String, dynamic>>()) {
              rows[_rowKey(table, row)] = row;
            }
          }
          final keys = rows.keys.toList()..sort();
          result[table] = keys.map((key) => rows[key]!).toList();
        }
        final bytes = _encodePackage(_format, result);
        if (increment.data['result'] != _hash(bytes)) {
          throw const FormatException('增量备份恢复校验失败');
        }
        return bytes;
      } on TypeError {
        throw const FormatException('备份的增量记录无效');
      }
    });
