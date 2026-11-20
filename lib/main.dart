import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart';

import 'dart:io';

import 'app.dart';
import 'core/settings.dart';
import 'playback/documents.dart';
import 'playback/playback_controller.dart';
import 'library/database.dart';
import 'library/library_controller.dart';

Future<PlaybackController>? _playback;
bool _nativeLicensesRegistered = false;

Future<PlaybackController> initializePlayback({
  PreferencesSettingsStore? settings,
}) async {
  MediaKit.ensureInitialized();
  final controller = PlaybackController(
    Player(),
    DocumentAccess(),
    volumeStore: Platform.isWindows
        ? settings ?? PreferencesSettingsStore()
        : null,
  );
  if (Platform.isAndroid) {
    await AudioService.init(
      builder: () => TagAudioHandler(controller),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'app.tagmusic.player.audio',
        androidNotificationChannelName: '音乐播放',
        androidNotificationIcon: 'drawable/ic_notification',
        androidStopForegroundOnPause: false,
      ),
    );
  }
  await controller.initialize();
  if (Platform.isWindows) {
    const MethodChannel('tag_music/tray').setMethodCallHandler((call) {
      return switch (call.method) {
        'previous' => controller.previous(),
        'togglePlayback' => controller.togglePlayPause(),
        'next' => controller.next(),
        _ => throw MissingPluginException(call.method),
      };
    });
  }
  return controller;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('R2 FlutterError: ${details.exceptionAsString()}');
  };
  if (!_nativeLicensesRegistered) {
    _nativeLicensesRegistered = true;
    LicenseRegistry.addLicense(() async* {
      for (final name in [
        'NOTICE.md',
        'LGPL-2.1.txt',
        'LGPL-3.0.txt',
        'GPL-3.0.txt',
        'mpv-Copyright.txt',
        'FFmpeg-LICENSE.md',
        'mbedTLS-LICENSE.txt',
        'libxml2-Copyright.txt',
      ]) {
        yield LicenseEntryWithLineBreaks([
          'native audio: mpv / FFmpeg / dependencies',
        ], await rootBundle.loadString('assets/licenses/native/$name'));
      }
    });
  }
  final store = PreferencesSettingsStore();
  var mode = ThemeMode.system;
  var themeColor = ThemeColor.blue;
  String? warning;
  PlaybackController? playback;
  LibraryController? library;
  try {
    playback = await (_playback ??= initializePlayback(settings: store));
  } catch (e) {
    _playback = null;
    warning = '播放初始化失败：$e';
  }
  try {
    library = LibraryController(
      LibraryDatabase(),
      playback?.documents ?? DocumentAccess(),
    );
    await library.initialize();
    playback?.resolveSong = library.resolveSong;
  } catch (e) {
    await library?.shutdown();
    library = null;
    warning = '${warning == null ? '' : '$warning\n'}曲库初始化失败：$e';
  }
  try {
    mode = decodeTheme(await store.readTheme());
  } catch (_) {
    warning =
        '${warning == null ? '' : '$warning\n'}无法读取主题设置，当前跟随系统。请检查存储空间后重新启动。';
  }
  try {
    themeColor = ThemeColor.decode(await store.readThemeColor());
  } catch (_) {
    warning = '${warning == null ? '' : '$warning\n'}无法读取主题色，当前使用海蓝。';
  }
  runApp(
    ProviderScope(
      overrides: [
        settingsStoreProvider.overrideWithValue(store),
        initialThemeProvider.overrideWithValue(mode),
        themeColorStoreProvider.overrideWithValue(store),
        initialThemeColorProvider.overrideWithValue(themeColor),
        startupWarningProvider.overrideWithValue(warning),
        playbackProvider.overrideWithValue(playback),
        libraryProvider.overrideWithValue(library),
      ],
      child: const TagMusicApp(),
    ),
  );
}
