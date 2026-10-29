import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/core/settings.dart';

class MemorySettings implements SettingsStore {
  String? value;
  bool failWrites = false;

  @override
  Future<String?> readTheme() async => value;

  @override
  Future<void> writeTheme(String value) async {
    if (failWrites) throw StateError('disk full');
    this.value = value;
  }
}

void main() {
  test('unknown or absent theme safely follows the system', () {
    expect(decodeTheme(null), ThemeMode.system);
    expect(decodeTheme('invalid'), ThemeMode.system);
    expect(decodeTheme('dark'), ThemeMode.dark);
  });

  test('persisted theme restores in a new application container', () async {
    final store = MemorySettings();
    final first = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    await first.read(themeProvider.notifier).select(ThemeMode.dark);
    expect(first.read(themeProvider), ThemeMode.dark);
    first.dispose();
    final restarted = ProviderContainer(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        initialThemeProvider.overrideWithValue(
          decodeTheme(await store.readTheme()),
        ),
      ],
    );
    addTearDown(restarted.dispose);
    expect(restarted.read(themeProvider), ThemeMode.dark);
  });

  test('failed save preserves last successfully stored theme', () async {
    final store = MemorySettings();
    final container = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await container.read(themeProvider.notifier).select(ThemeMode.light);
    store.failWrites = true;
    await expectLater(
      container.read(themeProvider.notifier).select(ThemeMode.dark),
      throwsStateError,
    );
    expect(container.read(themeProvider), ThemeMode.light);
    expect(store.value, 'light');
  });
}
