import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../playback/playback_controller.dart';
import 'library_controller.dart';
import 'song_file_editor.dart';

class SongEditorPage extends StatefulWidget {
  const SongEditorPage({
    super.key,
    this.library,
    this.playback,
    this.menuButton,
    this.editor = const SongFileEditor(),
  });

  final LibraryController? library;
  final PlaybackController? playback;
  final Widget? menuButton;
  final SongFileEditor editor;

  @override
  State<SongEditorPage> createState() => _SongEditorPageState();
}

class _SongEditorPageState extends State<SongEditorPage> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _artist = TextEditingController();
  final _album = TextEditingController();
  SongFileDraft? _draft;
  Uint8List? _cover;
  String? _parent;
  String? _pending;
  String? _notice;
  bool _failed = false;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  Future<void> _run(String status, Future<void> Function() action) async {
    if (_pending != null) return;
    setState(() {
      _pending = status;
      _notice = null;
      _failed = false;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _notice = switch (error) {
          PlatformException() => error.message ?? '无法访问文件',
          FormatException() => error.message,
          _ => error.toString(),
        };
      });
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  Future<void> _chooseSong() => _run('正在读取歌曲…', () async {
    final result = await widget.editor.pickSong();
    if (result == null || !mounted) return;
    setState(() {
      _draft = result;
      _parent = null;
      _cover = null;
      _title.text = result.metadata.title ?? '';
      _artist.text = result.metadata.artist ?? '';
      _album.text = result.metadata.album ?? '';
    });
  });

  Future<void> _chooseCover() => _run('正在压缩封面…', () async {
    final result = await widget.editor.pickCover();
    if (result != null && mounted) setState(() => _cover = result);
  });

  String? _fileName(SongFileDraft draft) {
    if (_title.text.trim().isEmpty || _artist.text.trim().isEmpty) return null;
    try {
      return editedSongName(
        _title.text.trim(),
        _artist.text.trim(),
        draft.file.extension,
      );
    } on SongEditorException {
      return null;
    }
  }

  Future<void> _save(SongFileDraft draft) async {
    if (_form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    final edits = (
      title: _title.text.trim(),
      artist: _artist.text.trim(),
      album: _album.text.trim(),
      cover: _cover,
    );
    await _run('正在保存歌曲…', () async {
      editedSongName(edits.title, edits.artist, draft.file.extension);
      if (_isCurrentSong(draft.file)) {
        throw const SongEditorException('播放器正在使用这首歌，请切换到其他歌曲后再保存');
      }
      if (Platform.isAndroid && _parent == null) {
        final parent = await widget.editor.pickParent(draft.file);
        if (parent == null || !mounted) return;
        _parent = parent;
      }
      Future<SavedSongFile> save() {
        if (_isCurrentSong(draft.file)) {
          throw const SongEditorException('播放器正在使用这首歌，请切换到其他歌曲后再保存');
        }
        return widget.editor.save(draft, edits, parent: _parent);
      }

      try {
        final library = widget.library;
        final (saved, synced) = library == null
            ? (await save(), true)
            : await library.editSongFile(draft.file, save);
        if (!mounted) return;
        setState(() {
          _draft = saved.draft;
          _cover = null;
          _notice = [
            '已保存 ${saved.draft.file.name}',
            if (!synced) '曲库同步失败，请检查曲库后再扫描。',
            if (saved.backup case final backup?) '原文件副本保留在同一文件夹，文件名为 $backup。',
          ].join('\n');
          _failed = !synced;
        });
      } on PlatformException {
        _parent = null;
        rethrow;
      }
    });
  }

  bool _isCurrentSong(EditableSongFile file) {
    final playback = widget.playback;
    final location = playback?.current?.location;
    if (location == null) return false;
    if (Platform.isAndroid) {
      final uri = Uri.tryParse(location);
      final selected = Uri.tryParse(file.location);
      return uri != null &&
          selected != null &&
          uri.authority == selected.authority &&
          uri.pathSegments.isNotEmpty &&
          selected.pathSegments.isNotEmpty &&
          uri.pathSegments.last == selected.pathSegments.last;
    }
    return file.identity ==
        (Platform.isWindows ? location.toLowerCase() : location);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final enabled = _pending == null;
    final theme = Theme.of(context);
    final status = _pending ?? _notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: Row(
            children: [
              ?widget.menuButton,
              const SizedBox(width: 16),
              Expanded(child: Text('编辑歌曲', style: theme.textTheme.titleLarge)),
              if (draft != null)
                IconButton(
                  onPressed: enabled ? _chooseSong : null,
                  tooltip: '选择另一首歌曲',
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (!enabled) const LinearProgressIndicator(),
        Expanded(
          child: draft == null
              ? Center(
                  child: FilledButton.tonalIcon(
                    onPressed: enabled ? _chooseSong : null,
                    icon: const Icon(Icons.add),
                    label: const Text('选择歌曲'),
                  ),
                )
              : _editor(draft, enabled),
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Semantics(
              liveRegion: true,
              child: Text(
                status,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _failed ? theme.colorScheme.error : null,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _editor(SongFileDraft draft, bool enabled) {
    final cover = _cover ?? draft.metadata.pictureBytes;
    final fileName = _fileName(draft);
    final theme = Theme.of(context);
    final placeholder = Icon(
      Icons.album_outlined,
      size: 56,
      color: theme.colorScheme.onSurfaceVariant,
    );
    final artwork = Column(
      children: [
        Container(
          width: 170,
          height: 170,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: cover == null
              ? placeholder
              : Image.memory(
                  cover,
                  width: 170,
                  height: 170,
                  cacheWidth: 500,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => placeholder,
                ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: enabled ? _chooseCover : null,
          icon: const Icon(Icons.image_outlined),
          label: const Text('选择封面'),
        ),
      ],
    );
    final fields = Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(_title, '歌名', enabled, required: true),
          const SizedBox(height: 16),
          _field(_artist, '歌手', enabled, required: true),
          const SizedBox(height: 16),
          _field(_album, '专辑', enabled),
          const SizedBox(height: 16),
          Text(
            fileName == null ? '保存时按「歌名-歌手」命名' : '保存文件名  $fileName',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (Platform.isAndroid && _parent == null) ...[
            const SizedBox(height: 8),
            const Text('保存时请选择歌曲所在的文件夹。'),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: enabled ? () => _save(draft) : null,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                draft.file.name,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) => constraints.maxWidth >= 460
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          artwork,
                          const SizedBox(width: 24),
                          Expanded(child: fields),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [artwork, const SizedBox(height: 16), fields],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    bool enabled, {
    bool required = false,
  }) => TextFormField(
    controller: controller,
    enabled: enabled,
    decoration: InputDecoration(labelText: label),
    inputFormatters: [
      FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
    ],
    validator: required
        ? (text) => text?.trim().isNotEmpty == true ? null : '请输入$label'
        : null,
    onChanged: (_) => setState(() {}),
  );
}
