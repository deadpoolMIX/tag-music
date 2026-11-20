import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class _LibrarySearchState extends State<LibrarySearch> {
  final _editing = TextEditingController();
  final _focus = FocusNode();
  bool _open = false;

  void _start() {
    setState(() => _open = true);
    _focus.requestFocus();
  }

  void _close() {
    _focus.unfocus();
    setState(() {
      _open = false;
      _editing.clear();
    });
    widget.onQueryChanged?.call();
  }

  @override
  void dispose() {
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
    return widget.builder(
      context,
      _editing.text.trim().toLowerCase(),
      field,
      IconButton(
        key: widget.buttonKey,
        tooltip: _open ? '关闭搜索' : widget.hintText,
        onPressed: _open ? _close : _start,
        icon: Icon(_open ? Icons.close : Icons.search),
      ),
    );
  }
}
