import 'package:drift/drift.dart';

import 'database.dart';
import 'filter_rule.dart';

class FilterRepository {
  FilterRepository(this.db);
  final LibraryDatabase db;

  Future<FilterPreferences> load() async {
    final row = await db.select(db.currentFilters).getSingleOrNull();
    if (row == null) return FilterPreferences();
    final sort = LibrarySort.values
        .where((v) => v.name == row.sortOrder)
        .firstOrNull;
    if (sort == null) throw const FormatException('筛选排序记录损坏');
    return FilterPreferences(
      rule: FilterRule.decode(row.ruleJson),
      sort: sort,
      descending: row.descending,
    );
  }

  Future<void> save(FilterPreferences preferences) => db
      .into(db.currentFilters)
      .insertOnConflictUpdate(
        CurrentFiltersCompanion.insert(
          id: const Value(1),
          ruleJson: preferences.rule.encode(),
          sortOrder: Value(preferences.sort.name),
          descending: Value(preferences.descending),
        ),
      );
}
