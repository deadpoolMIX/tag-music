import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../playback/documents.dart';
import 'library_controller.dart';

/// Own the editing session independently of scan results and player updates.
class LibrarySearch extends StatefulWidget {
  const LibrarySearch({
    required this.library,
    required this.documents,
    super.key,
  });
  final LibraryController library;
  final DocumentAccess documents;
  @override
  State<LibrarySearch> createState() => _LibrarySearchState();
}

class _LibrarySearchState extends State<LibrarySearch> {
  late final _editing = TextEditingController(text: widget.library.query);
  final _focus = FocusNode(debugLabel: 'library-search');
  Timer? _diagnostic;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    _diagnostic?.cancel();
    _diagnostic = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted) return;
      try {
        debugPrint(
          'R2 ${jsonEncode({'event': 'searchInput', 'focused': _focus.hasFocus, 'native': await widget.documents.diagnostics()})}',
        );
      } catch (e) {
        debugPrint('R2 searchInput diagnostics: $e');
      }
    });
  }

  @override
  void dispose() {
    _diagnostic?.cancel();
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    _editing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: const ValueKey('library-search'),
    controller: _editing,
    focusNode: _focus,
    keyboardType: TextInputType.text,
    textInputAction: TextInputAction.search,
    onChanged: (v) => widget.library.filter(text: v),
    decoration: InputDecoration(
      isDense: true,
      prefixIcon: const Icon(Icons.search),
      hintText: '搜索歌曲、歌手、专辑或文件名',
      suffixIcon: IconButton(
        tooltip: '清空搜索',
        onPressed: () {
          _editing.clear();
          widget.library.filter(text: '');
          _focus.requestFocus();
        },
        icon: const Icon(Icons.clear),
      ),
    ),
  );
}
