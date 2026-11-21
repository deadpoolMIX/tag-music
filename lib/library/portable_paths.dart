String? portableFolderName(String root) {
  var path = root;
  if (root.startsWith('content://')) {
    final parts = Uri.tryParse(root)?.pathSegments;
    final tree = parts?.indexOf('tree') ?? -1;
    if (parts == null || tree < 0 || tree + 1 >= parts.length) return null;
    path = parts[tree + 1];
    final volume = path.indexOf(':');
    if (volume < 0) return null;
    path = path.substring(volume + 1);
  }
  final name = path
      .split(RegExp(r'[/\\]'))
      .where((s) => s.isNotEmpty)
      .lastOrNull;
  return name == null || name.endsWith(':') ? null : name.toLowerCase();
}

String portableRelativePath(String root, String path) =>
    (root.startsWith('content://') ? path : path.replaceAll('\\', '/'))
        .toLowerCase();

/// Use a unique positive match on both sides. In particular, an album with
/// two encodings, or two folders with the same name, can be ambiguous.
Map<String, String> uniqueMusicMatches(
  Map<String, Set<String>> left,
  Map<String, Set<String>> right,
) {
  Map<String, String?> index(Map<String, Set<String>> side) {
    final result = <String, String?>{};
    for (final MapEntry(key: id, value: keys) in side.entries) {
      for (final key in keys) {
        result[key] = result.containsKey(key) ? null : id;
      }
    }
    return result;
  }

  final leftIndex = index(left);
  final rightIndex = index(right);
  final candidates = <String, Set<String>>{};
  final reverse = <String, Set<String>>{};
  for (final MapEntry(key: key, value: from) in leftIndex.entries) {
    final to = rightIndex[key];
    if (from == null || to == null) continue;
    if (!key.startsWith('sha256:')) {
      final leftDigest = left[from]!
          .where((id) => id.startsWith('sha256:'))
          .firstOrNull;
      final rightDigest = right[to]!
          .where((id) => id.startsWith('sha256:'))
          .firstOrNull;
      if (leftDigest != null &&
          rightDigest != null &&
          leftDigest != rightDigest) {
        continue;
      }
    }
    (candidates[from] ??= {}).add(to);
    (reverse[to] ??= {}).add(from);
  }
  return {
    for (final MapEntry(key: from, value: to) in candidates.entries)
      if (to.length == 1 && reverse[to.single]!.length == 1) from: to.single,
  };
}
