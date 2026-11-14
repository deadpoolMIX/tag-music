import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics.dart';
import 'core/settings.dart';
import 'playback/playback_minibar.dart';
import 'library/library_page.dart';
import 'library/filter_page.dart';
import 'library/playlists_page.dart';
import 'playback/playback_controller.dart';
import 'library/library_controller.dart';
import 'library/tags_page.dart';
import 'library/group_pages.dart';

final _appNavigator = GlobalKey<NavigatorState>();

class TagMusicApp extends ConsumerWidget {
  const TagMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    navigatorKey: _appNavigator,
    builder: (context, child) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _appNavigator.currentState?.maybePop(),
      },
      child: child!,
    ),
    title: 'Tag Music',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    themeMode: ref.watch(themeProvider),
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const AppShell(),
  );

  ThemeData _theme(Brightness brightness) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF386A56),
      brightness: brightness,
    ),
    fontFamily: 'Microsoft YaHei',
  );
}

enum AppDestination {
  songs,
  filter,
  playlists,
  albums,
  artists,
  tags,
  settings,
}

const _destinations = [
  (Icons.library_music_outlined, '歌曲'),
  (Icons.filter_alt_outlined, '筛选'),
  (Icons.queue_music_outlined, '歌单'),
  (Icons.album_outlined, '专辑'),
  (Icons.person_outline, '歌手'),
  (Icons.sell_outlined, '标签'),
  (Icons.settings_outlined, '设置'),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  AppDestination _selected = AppDestination.songs;
  final _scaffold = GlobalKey<ScaffoldState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(playbackProvider)?.refreshNotificationPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _navigation(bool compact, {bool drawer = false}) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            for (final destination in AppDestination.values) ...[
              if (destination == AppDestination.settings)
                const Divider(height: 28),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: destination == _selected
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: Tooltip(
                    message: _destinations[destination.index].$2,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setState(() => _selected = destination);
                        if (drawer) Navigator.of(context).pop();
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _destinations[destination.index].$1,
                              semanticLabel: compact
                                  ? _destinations[destination.index].$2
                                  : null,
                            ),
                            if (!compact) ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  _destinations[destination.index].$2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = Theme.of(context).platform == TargetPlatform.windows;
      final library = ref.watch(libraryProvider);
      final playback = ref.watch(playbackProvider);
      Widget unavailable() => const Center(child: Text('曲库尚未就绪'));
      Widget branch(AppDestination destination) => KeyedSubtree(
        key: ValueKey(destination),
        child: switch (destination) {
          AppDestination.songs =>
            library == null || playback == null
                ? unavailable()
                : LibraryPage(
                    library: library,
                    playback: playback,
                    menuButton: desktop
                        ? null
                        : IconButton(
                            key: const ValueKey('open-navigation'),
                            tooltip: '打开导航菜单',
                            onPressed: () =>
                                _scaffold.currentState?.openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                  ),
          AppDestination.filter =>
            library == null || playback == null
                ? unavailable()
                : FilterPage(library: library, playback: playback),
          AppDestination.playlists =>
            library == null || playback == null
                ? unavailable()
                : PlaylistsPage(
                    library: library,
                    playback: playback,
                    active: _selected == AppDestination.playlists,
                  ),
          AppDestination.tags =>
            library == null || playback == null
                ? unavailable()
                : TagsPage(
                    library: library,
                    playback: playback,
                    active: _selected == AppDestination.tags,
                  ),
          AppDestination.settings => const SettingsPage(),
          AppDestination.albums || AppDestination.artists =>
            library == null || playback == null
                ? unavailable()
                : MetadataGroupsPage(
                    library: library,
                    playback: playback,
                    albums: destination == AppDestination.albums,
                    active: _selected == destination,
                  ),
        },
      );
      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Scaffold(
                key: _scaffold,
                drawer: desktop
                    ? null
                    : Drawer(
                        width: constraints.maxWidth * .52,
                        child: _navigation(false, drawer: true),
                      ),
                drawerScrimColor: Colors.black26,
                body: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      if (desktop)
                        SizedBox(
                          width: constraints.maxWidth >= 1000 ? 190 : 72,
                          child: _navigation(constraints.maxWidth < 1000),
                        ),
                      if (desktop) const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            if (!desktop &&
                                (_selected != AppDestination.songs ||
                                    library == null ||
                                    playback == null))
                              Align(
                                alignment: Alignment.centerLeft,
                                child: IconButton(
                                  key: const ValueKey('open-navigation'),
                                  tooltip: '打开导航菜单',
                                  onPressed: () =>
                                      _scaffold.currentState?.openDrawer(),
                                  icon: const Icon(Icons.menu),
                                ),
                              ),
                            if (ref.watch(startupWarningProvider)
                                case final warning?)
                              MaterialBanner(
                                content: Text(warning),
                                actions: [
                                  TextButton(
                                    onPressed: () => setState(
                                      () => _selected = AppDestination.settings,
                                    ),
                                    child: const Text('查看设置'),
                                  ),
                                ],
                              ),
                            if (playback != null)
                              ListenableBuilder(
                                listenable: playback,
                                builder: (_, _) => Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (playback.error != null ||
                                        playback.playbackNotice != null)
                                      Text(
                                        playback.error ??
                                            playback.playbackNotice!,
                                        key: const ValueKey('playback-error'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (!playback.notificationsEnabled)
                                      Text(
                                        playback.notificationMessage ??
                                            '允许播放通知后，可在通知栏和锁屏控制音乐。',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (!playback.notificationsEnabled)
                                      TextButton(
                                        onPressed: playback
                                            .requestNotificationPermission,
                                        child: const Text('开启播放通知'),
                                      ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: IndexedStack(
                                index: _selected.index,
                                children: [
                                  for (final destination
                                      in AppDestination.values)
                                    branch(destination),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const PlaybackMinibar(),
          ],
        ),
      );
    },
  );
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _saving = false;

  Future<void> _select(ThemeMode mode) async {
    setState(() => _saving = true);
    try {
      await ref.read(themeProvider.notifier).select(mode);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('主题保存失败，请检查存储空间后重试。')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeProvider);
    final package = ref.watch(packageInfoProvider);
    final playback = ref.watch(playbackProvider);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('设置', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
            Text('外观', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final option in [
                  (ThemeMode.system, '跟随系统', Icons.brightness_auto),
                  (ThemeMode.light, '浅色', Icons.light_mode_outlined),
                  (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
                ])
                  ChoiceChip(
                    key: ValueKey('theme-${option.$1.name}'),
                    avatar: Icon(option.$3, size: 18),
                    label: Text(option.$2),
                    selected: mode == option.$1,
                    onSelected: _saving ? null : (_) => _select(option.$1),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('主题会在下次启动和覆盖安装后保留。'),
            if (playback?.documents.android == true) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: playback!.openNotificationSettings,
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('播放通知设置'),
              ),
            ],
            if (ref.watch(libraryProvider) case final library?) ...[
              const SizedBox(height: 24),
              DirectorySettings(library: library),
            ],
            const SizedBox(height: 32),
            Text('关于', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: package.when(
                  loading: () => const Text('正在读取版本信息…'),
                  error: (error, stack) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('版本信息读取失败'),
                      TextButton(
                        onPressed: () => ref.invalidate(packageInfoProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                  data: (info) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tag Music'),
                      const SizedBox(height: 8),
                      SelectableText('版本 ${info.version}+${info.buildNumber}'),
                      const SizedBox(height: 8),
                      const Text('R5 · 歌单与队列'),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        key: const ValueKey('copy-diagnostics'),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('复制诊断信息'),
                        onPressed: () async {
                          try {
                            await Clipboard.setData(
                              ClipboardData(text: diagnosticReport(info)),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('诊断信息已复制')),
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('复制失败，请重试。')),
                              );
                            }
                          }
                        },
                      ),
                      TextButton(
                        onPressed: () => showLicensePage(
                          context: context,
                          applicationName: 'Tag Music',
                          applicationVersion:
                              '${info.version}+${info.buildNumber}',
                          applicationLegalese: '原创代码采用 MIT 许可；第三方组件保留各自许可。',
                        ),
                        child: const Text('开源许可'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text('音乐文件由你保管，管理数据保存在本机。'),
          ],
        ),
      ),
    );
  }
}
