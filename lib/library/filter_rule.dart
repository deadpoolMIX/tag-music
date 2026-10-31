import 'dart:convert';

enum LibrarySort { title, artist, album, name }

/// Fixed three-box filter. An absent include box contributes no union operand.
class FilterRule {
  FilterRule({
    Iterable<String> allTagIds = const [],
    Iterable<String> anyTagIds = const [],
    Iterable<String> excludedTagIds = const [],
  }) : allTagIds = Set.unmodifiable(allTagIds),
       anyTagIds = Set.unmodifiable(anyTagIds),
       excludedTagIds = Set.unmodifiable(excludedTagIds);

  final Set<String> allTagIds;
  final Set<String> anyTagIds;
  final Set<String> excludedTagIds;
  Set<String> get referencedIds => {
    ...allTagIds,
    ...anyTagIds,
    ...excludedTagIds,
  };
  bool get isEmpty => referencedIds.isEmpty;

  bool matches(Set<String> tags) {
    final included =
        (allTagIds.isEmpty && anyTagIds.isEmpty) ||
        (allTagIds.isNotEmpty && allTagIds.every(tags.contains)) ||
        anyTagIds.any(tags.contains);
    return included && !excludedTagIds.any(tags.contains);
  }

  Set<String> evaluate(
    Iterable<String> availableSongIds,
    Map<String, Set<String>> tagsBySong,
  ) => {
    for (final id in availableSongIds)
      if (matches(tagsBySong[id] ?? const {})) id,
  };

  FilterRule without(String tagId) => FilterRule(
    allTagIds: allTagIds.where((id) => id != tagId),
    anyTagIds: anyTagIds.where((id) => id != tagId),
    excludedTagIds: excludedTagIds.where((id) => id != tagId),
  );

  String encode() => jsonEncode({
    'version': 1,
    'allTagIds': allTagIds.toList()..sort(),
    'anyTagIds': anyTagIds.toList()..sort(),
    'excludedTagIds': excludedTagIds.toList()..sort(),
  });

  factory FilterRule.decode(String value) {
    final data = jsonDecode(value);
    if (data is! Map<String, dynamic> || data['version'] != 1) {
      throw const FormatException('筛选规则版本不受支持');
    }
    List<String> ids(String key) {
      final values = data[key];
      if (values is! List || values.any((v) => v is! String || v.isEmpty)) {
        throw const FormatException('筛选标签记录损坏');
      }
      return values.cast<String>();
    }

    return FilterRule(
      allTagIds: ids('allTagIds'),
      anyTagIds: ids('anyTagIds'),
      excludedTagIds: ids('excludedTagIds'),
    );
  }
}

class FilterPreferences {
  FilterPreferences({
    FilterRule? rule,
    this.sort = LibrarySort.title,
    this.descending = false,
  }) : rule = rule ?? FilterRule();
  final FilterRule rule;
  final LibrarySort sort;
  final bool descending;

  FilterPreferences without(String tagId) => FilterPreferences(
    rule: rule.without(tagId),
    sort: sort,
    descending: descending,
  );
}
