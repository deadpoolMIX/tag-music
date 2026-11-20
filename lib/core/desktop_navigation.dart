import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Recreate a page when the user follows the Windows forward history.
Future<void> pushAppPage(
  BuildContext context,
  PageRoute<void> Function() create,
) {
  final history = DesktopNavigation.maybeOf(context);
  final navigator = history?.navigator ?? Navigator.of(context);
  if (history != null) return history._push(navigator, create);
  return navigator.push<void>(create());
}

class DesktopNavigation extends NavigatorObserver {
  final _activeRoute = ValueNotifier<Route<dynamic>?>(null);
  ValueListenable<Route<dynamic>?> get activeRoute => _activeRoute;
  Route<dynamic>? get top => _activeRoute.value;
  final _pages = Expando<(Object, PageRoute<void> Function())>();
  final _forward = <(Object, VoidCallback)>[];
  final _local = <(ModalRoute<dynamic>, Object)>[];
  bool _replaying = false;

  static DesktopNavigation? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DesktopNavigationScope>()?.history;

  Object? _pageId(Route<dynamic>? route) =>
      route == null ? null : _pages[route]?.$1 ?? route;

  Future<void> _push(
    NavigatorState navigator,
    PageRoute<void> Function() create, {
    Object? id,
  }) {
    final route = create();
    _pages[route] = (id ?? Object(), create);
    return navigator.push<void>(route);
  }

  void back() => navigator?.maybePop();

  void forward() {
    if (_forward.isEmpty || !identical(_pageId(top), _forward.last.$1)) return;
    final (_, reopen) = _forward.removeLast();
    _replaying = true;
    try {
      reopen();
    } finally {
      _replaying = false;
    }
  }

  /// Keep shell sections in the same history as Navigator pages.
  void visit<T>(
    BuildContext context,
    Object section,
    T previous,
    T next,
    ValueChanged<T> show, {
    bool returning = false,
  }) {
    if (previous == next) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    if (returning && _local.isNotEmpty && _local.last == (route, section)) {
      back();
      return;
    }

    final page = (route, section);
    void open() {
      if (!_replaying) _forward.clear();
      _local.add(page);
      route.addLocalHistoryEntry(
        LocalHistoryEntry(
          impliesAppBarDismissal: false,
          onRemove: () {
            _local.removeLast();
            _forward.add((route, open));
            show(previous);
          },
        ),
      );
      show(next);
    }

    open();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute && !_replaying) _forward.clear();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final page = _pages[route];
    final parentId = _pageId(previousRoute);
    final activeNavigator = navigator;
    if (page != null && activeNavigator != null && parentId != null) {
      final (id, create) = page;
      _forward.add((parentId, () => _push(activeNavigator, create, id: id)));
    }
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _activeRoute.value = topRoute;
  }

  void dispose() => _activeRoute.dispose();
}

class DesktopNavigationScope extends InheritedWidget {
  const DesktopNavigationScope({
    required this.history,
    required super.child,
    super.key,
  });

  final DesktopNavigation history;

  @override
  bool updateShouldNotify(DesktopNavigationScope oldWidget) => false;
}
