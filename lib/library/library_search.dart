import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/desktop_navigation.dart';
import 'library_controller.dart';

List<LibraryTrack> searchSongRows(List<LibraryTrack> tracks, String query) =>
    query.isEmpty
    ? tracks
    : tracks.where((track) => track.matchesSearch(query)).toList();

/// Replace the heading in place while keeping the page and its actions mounted.
class LibrarySearch extends StatefulWidget {
  const LibrarySearch({
    required this.hintText,
    required this.builder,
    this.heading,
    this.buttonKey,
    this.fieldKey,
    this.onQueryChanged,
    super.key,
  });

  final String hintText;
  final Widget Function(
    BuildContext context,
    String query,
    Widget? heading,
    Widget searchButton,
  )
  builder;
  final Widget? heading;
  final Key? buttonKey;
  final Key? fieldKey;
  final VoidCallback? onQueryChanged;

  @override
  State<LibrarySearch> createState() => _LibrarySearchState();
}

class _LibrarySearchState extends State<LibrarySearch> with RouteAware {
  final _editing = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;
  RouteObserver<PageRoute<dynamic>>? _observer;
  PageRoute<dynamic>? _page;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!PageActivity.isActiveOf(context)) _clear();
    final observer = PageNavigationScope.of(context);
    final route = ModalRoute.of(context);
    final page = route is PageRoute<dynamic> ? route : null;
    if (identical(observer, _observer) && identical(page, _page)) return;
    _observer?.unsubscribe(this);
    _observer = observer;
    _page = page;
    if (page != null) observer?.subscribe(this, page);
  }

  @override
  void didPushNext() => _close();

  void _start() {
    setState(() => _open = true);
    _focus.requestFocus();
  }

  void _clear() {
    if (!_open) return;
    _open = false;
    _editing.clear();
    _focus.unfocus();
  }

  void _close() {
    if (!_open) return;
    setState(_clear);
    widget.onQueryChanged?.call();
  }

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    _focus.dispose();
    _editing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = _open
        ? CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): _close,
            },
            child: TextField(
              key: widget.fieldKey,
              controller: _editing,
              focusNode: _focus,
              onChanged: (_) {
                setState(() {});
                widget.onQueryChanged?.call();
              },
              onSubmitted: (_) => _focus.unfocus(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hintText,
              ),
            ),
          )
        : widget.heading;
    return PopScope<Object?>(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: widget.builder(
        context,
        _editing.text.trim().toLowerCase(),
        field,
        IconButton(
          key: widget.buttonKey,
          tooltip: _open ? '关闭搜索' : widget.hintText,
          onPressed: _open ? _close : _start,
          icon: Icon(_open ? Icons.close : Icons.search),
        ),
      ),
    );
  }
}
