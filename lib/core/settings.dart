import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SettingsStore {
  Future<String?> readTheme();
  Future<void> writeTheme(String value);
}

class PreferencesSettingsStore implements SettingsStore {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> readTheme() => _preferences.getString('settings.v1.theme');

  @override
  Future<void> writeTheme(String value) =>
      _preferences.setString('settings.v1.theme', value);
}

ThemeMode decodeTheme(String? value) => ThemeMode.values.firstWhere(
  (mode) => mode.name == value,
  orElse: () => ThemeMode.system,
);

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => PreferencesSettingsStore(),
);
final initialThemeProvider = Provider<ThemeMode>((ref) => ThemeMode.system);
final startupWarningProvider = Provider<String?>((ref) => null);
final themeProvider = NotifierProvider<ThemeController, ThemeMode>(
  ThemeController.new,
);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.watch(initialThemeProvider);

  Future<void> select(ThemeMode mode) async {
    await ref.read(settingsStoreProvider).writeTheme(mode.name);
    state = mode;
  }
}
