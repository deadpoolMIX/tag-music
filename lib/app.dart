import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics.dart';
import 'core/settings.dart';
import 'playback/cover_viewer.dart' show coverViewerRouteName;
import 'playback/full_player.dart' show fullPlayerRouteName, openFullPlayer;
import 'playback/playback_minibar.dart';
import 'playback/queue_page.dart' show playbackQueueRouteName;
import 'library/library_page.dart';
import 'library/filter_page.dart';
import 'library/playlists_page.dart';
import 'playback/playback_controller.dart';
import 'library/library_controller.dart';
import 'library/tags_page.dart';
import 'library/group_pages.dart';
import 'library/library_header.dart';

class TagMusicApp extends ConsumerStatefulWidget {
  const TagMusicApp({super.key});

  @override
  ConsumerState<TagMusicApp> createState() => _TagMusicAppState();
}

class _TagMusicAppState extends ConsumerState<TagMusicApp> {
  final _appNavigator = GlobalKey<NavigatorState>();
  final _shell = GlobalKey<_AppShellState>();
  final _routes = _TopRouteObserver();
  double _swipeStartX = 0;
  Route<dynamic>? _swipeRoute;

  bool _allowsNavigationSwipe(Route<dynamic>? route) =>
      route is PageRoute &&
      route.settings.name != fullPlayerRouteName &&
      route.settings.name != coverViewerRouteName &&
      route.settings.name != playbackQueueRouteName;

  void _handleMouseNavigation(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final navigator = _appNavigator.currentState;
    final top = _routes.top;
    if (navigator == null || top == null) return;
    if (event.buttons == kBackMouseButton &&
        top.settings.name == fullPlayerRouteName) {
      final showingLyrics = top.willHandlePopInternally;
      navigator.pop();
      if (showingLyrics && top.isCurrent) navigator.pop();
    } else if (event.buttons == kForwardMouseButton &&
        identical(top, _routes.playerForwardFrom)) {
      openFullPlayer(navigator.context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = ref.watch(themeColorProvider);
    return MaterialApp(
      navigatorKey: _appNavigator,
      navigatorObservers: [_routes],
      builder: (context, child) {
        final desktop = Theme.of(context).platform == TargetPlatform.windows;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _appNavigator.currentState?.maybePop(),
          },
          child: desktop
              ? Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleMouseNavigation,
                  child: child,
                )
              : RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  excludeFromSemantics: true,
                  gestures: {
                    _NavigationSwipeRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          _NavigationSwipeRecognizer
                        >(
                          () => _NavigationSwipeRecognizer(
                            () => _allowsNavigationSwipe(_routes.top),
                          ),
                          (recognizer) {
                            recognizer.dragStartBehavior =
                                DragStartBehavior.down;
                            recognizer.onStart = (details) {
                              _swipeStartX = details.globalPosition.dx;
                              _swipeRoute = _routes.top;
                            };
                            recognizer.onEnd = (details) {
                              final route = _routes.top;
                              if (details.globalPosition.dx - _swipeStartX >=
                                      56 &&
                                  identical(route, _swipeRoute) &&
                                  _allowsNavigationSwipe(route)) {
                                _shell.currentState?._openNavigation();
                              }
                            };
                          },
                        ),
                  },
                  child: child,
                ),
        );
      },
      title: 'Tag Music',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: ref.watch(themeProvider),
      theme: _theme(Brightness.light, color),
      darkTheme: _theme(Brightness.dark, color),
      home: AppShell(key: _shell),
    );
  }

  ThemeData _theme(Brightness brightness, ThemeColor color) {
    final generated = ColorScheme.fromSeed(
      seedColor: color.seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      primary: brightness == Brightness.light ? color.seed : null,
      onPrimary: brightness == Brightness.light ? Colors.white : null,
    );
    final scheme = brightness == Brightness.light
        ? generated.copyWith(
            surface: Colors.white,
            surfaceBright: Colors.white,
            surfaceDim: const Color(0xFFE1E3E6),
            surfaceContainerLowest: Colors.white,
            surfaceContainerLow: const Color(0xFFF7F8FA),
            surfaceContainer: const Color(0xFFF2F4F6),
            surfaceContainerHigh: const Color(0xFFECEEF1),
            surfaceContainerHighest: const Color(0xFFE5E8EC),
            onSurface: const Color(0xFF171A20),
            onSurfaceVariant: const Color(0xFF494E57),
          )
        : generated;
    return ThemeData(
      useMaterial3: true,
      dialogTheme: DialogThemeData(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titleTextStyle: TextStyle(
          fontFamily: 'Microsoft YaHei',
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: brightness == Brightness.dark ? Colors.white : Colors.black87,
        ),
      ),
      inputDecorationTheme: const InputDecorationThemeData(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        prefixIconConstraints: BoxConstraints(minWidth: 36, minHeight: 36),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        menuPadding: EdgeInsets.symmetric(vertical: 4),
      ),
      scaffoldBackgroundColor: scheme.surface,
      colorScheme: scheme,
      fontFamily: 'Microsoft YaHei',
    );
  }
}

class _NavigationSwipeRecognizer extends HorizontalDragGestureRecognizer {
  _NavigationSwipeRecognizer(this.canStart)
    : super(supportedDevices: const {PointerDeviceKind.touch});

  final bool Function() canStart;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canStart() && super.isPointerAllowed(event);
}

class _TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? top;
  Route<dynamic>? playerForwardFrom;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) playerForwardFrom = null;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == fullPlayerRouteName) {
      playerForwardFrom = previousRoute;
    } else if (identical(route, playerForwardFrom)) {
      playerForwardFrom = null;
    }
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    top = topRoute;
  }
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

  Future<void> _openNavigation() async {
    final scaffold = _scaffold.currentState;
    if (scaffold != null && ModalRoute.isCurrentOf(context) == true) {
      scaffold.openDrawer();
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    var swipeStartX = 0.0;
    final destination = await showGeneralDialog<AppDestination>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black26,
      pageBuilder: (drawerContext, _, _) => Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (details) =>
              swipeStartX = details.globalPosition.dx,
          onHorizontalDragEnd: (details) {
            if (swipeStartX - details.globalPosition.dx >= 56) {
              Navigator.of(drawerContext).pop();
            }
          },
          child: Drawer(
            width: MediaQuery.sizeOf(drawerContext).width * .52,
            child: _navigation(
              false,
              (destination) => Navigator.of(drawerContext).pop(destination),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: animation.drive(
          Tween(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)),
        ),
        child: child,
      ),
    );
    if (!mounted || destination == null) return;
    navigator.popUntil((route) => route.isFirst);
    _select(destination);
  }

  void _select(AppDestination destination) =>
      setState(() => _selected = destination);

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

  Widget _navigation(bool compact, ValueChanged<AppDestination> onSelect) =>
      SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            reverse: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
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
                              onTap: () => onSelect(destination),
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
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = Theme.of(context).platform == TargetPlatform.windows;
      final library = ref.watch(libraryProvider);
      final playback = ref.watch(playbackProvider);
      final menuButton = desktop
          ? null
          : IconButton(
              key: const ValueKey('open-navigation'),
              tooltip: '打开导航菜单',
              onPressed: _openNavigation,
              icon: const Icon(Icons.menu),
            );
      final libraryReady = library != null && playback != null;
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
                    menuButton: menuButton,
                  ),
          AppDestination.filter =>
            library == null || playback == null
                ? unavailable()
                : FilterPage(
                    library: library,
                    playback: playback,
                    menuButton: menuButton,
                  ),
          AppDestination.playlists =>
            library == null || playback == null
                ? unavailable()
                : PlaylistsPage(
                    library: library,
                    playback: playback,
                    active: _selected == AppDestination.playlists,
                    menuButton: menuButton,
                  ),
          AppDestination.tags =>
            library == null || playback == null
                ? unavailable()
                : TagsPage(
                    library: library,
                    playback: playback,
                    active: _selected == AppDestination.tags,
                    menuButton: menuButton,
                  ),
          AppDestination.settings => SettingsPage(menuButton: menuButton),
          AppDestination.albums || AppDestination.artists =>
            library == null || playback == null
                ? unavailable()
                : MetadataGroupsPage(
                    library: library,
                    playback: playback,
                    albums: destination == AppDestination.albums,
                    active: _selected == destination,
                    menuButton: menuButton,
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
                        child: _navigation(false, (destination) {
                          _select(destination);
                          _scaffold.currentState?.closeDrawer();
                        }),
                      ),
                drawerScrimColor: Colors.black26,
                body: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      if (desktop)
                        SizedBox(
                          width: constraints.maxWidth >= 1000 ? 190 : 72,
                          child: _navigation(
                            constraints.maxWidth < 1000,
                            _select,
                          ),
                        ),
                      if (desktop) const VerticalDivider(width: 1),
                      Expanded(
                        child: Column(
                          children: [
                            if (!desktop &&
                                _selected != AppDestination.settings &&
                                !libraryReady)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: menuButton,
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
  const SettingsPage({this.menuButton, super.key});
  final Widget? menuButton;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _saving = false;

  Future<void> _save(Future<void> Function() apply) async {
    setState(() => _saving = true);
    try {
      await apply();
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
    final color = ref.watch(themeColorProvider);
    final package = ref.watch(packageInfoProvider);
    final playback = ref.watch(playbackProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LibraryHeader(
          menuButton: widget.menuButton,
          heading: Padding(
            padding: EdgeInsetsDirectional.only(
              start: widget.menuButton == null ? 0 : 8,
            ),
            child: Text('设置', style: theme.textTheme.titleLarge),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                children: [
                  Text('外观', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: SegmentedButton<ThemeMode>(
                        expandedInsets: EdgeInsets.zero,
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: [
                          for (final option in [
                            (ThemeMode.system, '跟随系统', Icons.brightness_auto),
                            (ThemeMode.light, '浅色', Icons.light_mode_outlined),
                            (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
                          ])
                            ButtonSegment(
                              value: option.$1,
                              icon: Icon(option.$3, size: 16),
                              label: Text(
                                option.$2,
                                key: ValueKey('theme-${option.$1.name}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        selected: {mode},
                        onSelectionChanged: _saving
                            ? null
                            : (selected) => _save(
                                () => ref
                                    .read(themeProvider.notifier)
                                    .select(selected.single),
                              ),
                      ),
                    ),
                  ),
                  Text('主题色', style: theme.textTheme.titleMedium),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in ThemeColor.values)
                        ChoiceChip(
                          avatar: CircleAvatar(backgroundColor: option.seed),
                          label: Text(option.label),
                          selected: color == option,
                          showCheckmark: false,
                          onSelected: _saving
                              ? null
                              : (_) => _save(
                                  () => ref
                                      .read(themeColorProvider.notifier)
                                      .select(option),
                                ),
                        ),
                    ],
                  ),
                  if (playback?.documents.android == true) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: playback!.openNotificationSettings,
                        icon: const Icon(Icons.notifications_outlined),
                        label: const Text('播放通知设置'),
                      ),
                    ),
                  ],
                  if (ref.watch(libraryProvider) case final library?) ...[
                    const SizedBox(height: 4),
                    DirectorySettings(library: library),
                  ],
                  const SizedBox(height: 12),
                  Text('关于', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: package.when(
                        loading: () => const Text('正在读取版本信息…'),
                        error: (error, stack) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('版本信息读取失败'),
                            TextButton(
                              onPressed: () =>
                                  ref.invalidate(packageInfoProvider),
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                        data: (info) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              'Tag Music · ${info.version}+${info.buildNumber}',
                            ),
                            Wrap(
                              children: [
                                TextButton.icon(
                                  key: const ValueKey('copy-diagnostics'),
                                  icon: const Icon(Icons.copy_outlined),
                                  label: const Text('复制诊断信息'),
                                  onPressed: () async {
                                    try {
                                      await Clipboard.setData(
                                        ClipboardData(
                                          text: diagnosticReport(info),
                                        ),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text('诊断信息已复制'),
                                              ),
                                            );
                                      }
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text('复制失败，请重试。'),
                                              ),
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
                                    applicationLegalese:
                                        '原创代码采用 MIT 许可；第三方组件保留各自许可。',
                                  ),
                                  child: const Text('开源许可'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
