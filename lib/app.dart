import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/diagnostics.dart';
import 'core/settings.dart';
import 'playback/playback_page.dart';
import 'playback/playback_controller.dart';
import 'library/library_controller.dart';
import 'library/tags_page.dart';

class TagMusicApp extends ConsumerWidget {
  const TagMusicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
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

const _destinations = [
  (Icons.library_music_outlined, Icons.library_music, '曲库'),
  (Icons.sell_outlined, Icons.sell, '标签'),
  (Icons.queue_music_outlined, Icons.queue_music, '歌单'),
  (Icons.settings_outlined, Icons.settings, '设置'),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _selected = 0;

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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 840;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Tag Music'),
          actions: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Chip(label: Text('R3 · 标签管理')),
            ),
          ],
        ),
        body: Row(
          children: [
            if (wide) ...[
              NavigationRail(
                extended: constraints.maxWidth >= 1100,
                selectedIndex: _selected,
                labelType: constraints.maxWidth >= 1100
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                onDestinationSelected: (index) =>
                    setState(() => _selected = index),
                destinations: [
                  for (final item in _destinations)
                    NavigationRailDestination(
                      icon: Icon(item.$1),
                      selectedIcon: Icon(item.$2),
                      label: Text(item.$3),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                children: [
                  if (ref.watch(startupWarningProvider) case final warning?)
                    MaterialBanner(
                      content: Text(warning),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _selected = 3),
                          child: const Text('查看设置'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: _selected == 3
                        ? const SettingsPage()
                        : _selected == 0
                        ? const PlaybackPage()
                        : _selected == 1
                        ? switch (ref.watch(libraryProvider)) {
                            final library? => TagsPage(library: library),
                            null => const Center(child: Text('曲库尚未就绪')),
                          }
                        : EmptyPage(index: _selected),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _selected,
                onDestinationSelected: (index) =>
                    setState(() => _selected = index),
                destinations: [
                  for (final item in _destinations)
                    NavigationDestination(
                      icon: Icon(item.$1),
                      selectedIcon: Icon(item.$2),
                      label: item.$3,
                    ),
                ],
              ),
      );
    },
  );
}

class EmptyPage extends StatelessWidget {
  const EmptyPage({required this.index, super.key});
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titles = ['让音乐有自己的归属', '用标签连接每一种喜好', '留住每一次灵感'];
    final descriptions = [
      '这里将收纳你的本地音乐。\n目录导入与播放将在后续版本开放。',
      '这里将管理音乐的多个标签。',
      '这里将保存普通歌单和智能歌单。\n歌单与队列将在 R5 开放。',
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(
                  _destinations[index].$1,
                  size: 56,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                titles[index],
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                descriptions[index],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.7),
              ),
              const SizedBox(height: 32),
              const Text('本地音乐 · 多标签 · 自由组合'),
            ],
          ),
        ),
      ),
    );
  }
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
                      const Text('R3 · 标签管理'),
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
