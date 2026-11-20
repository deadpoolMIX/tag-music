import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/compact_dialog.dart';
import '../playback/documents.dart';
import 'database.dart';
import 'library_controller.dart';
import 'library_relocation.dart';

Future<void> showDirectoryRelocation(
  BuildContext context,
  LibraryController library,
  LibraryRoot root,
) => _run(context, library, (relocation) async {
  final target = await library.documents.selectMusicDirectory(temporary: true);
  if (!context.mounted || target == null) return null;
  final plan = await _inspect(
    context,
    library,
    '查找可关联的歌曲',
    (cancelled, progress) => relocation.previewDirectory(
      root.location,
      target,
      cancelled: cancelled,
      progress: progress,
    ),
  );
  if (!context.mounted || plan == null) return null;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => _DirectoryPreview(plan),
  );
  if (!context.mounted || confirmed != true) return null;
  final applied = await _inspect(
    context,
    library,
    '重新关联歌曲',
    (cancelled, progress) => relocation.applyDirectory(
      plan,
      cancelled: cancelled,
      progress: progress,
    ),
    keepResultOnCancel: true,
  );
  if (applied != true) return null;
  return '已关联 ${plan.matches.length} 首。'
      '${plan.unmatched.isEmpty ? '' : '还有 ${plan.unmatched.length} 首待处理。'}';
});

Future<void> showSongRelocation(
  BuildContext context,
  LibraryController library,
  Song song,
) => _run(context, library, (relocation) async {
  final target = await library.documents.selectMusicDirectory(temporary: true);
  if (!context.mounted || target == null) return null;
  final files = await _inspect(
    context,
    library,
    '读取所选目录',
    (cancelled, progress) =>
        relocation.listFiles(target, cancelled: cancelled, progress: progress),
  );
  if (!context.mounted || files == null) return null;
  if (files.isEmpty) return '所选目录中没有可关联的音乐文件。';
  files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  final occupied = {
    for (final track in library.tracks)
      if (track.song.id != song.id) track.song.identity,
  };
  final file = await showDialog<ScannedFile>(
    context: context,
    builder: (_) => _SongPicker(song: song, files: files, occupied: occupied),
  );
  if (!context.mounted || file == null) return null;
  final applied = await _inspect(
    context,
    library,
    '重新关联歌曲',
    (cancelled, progress) => relocation.applySingle(
      target,
      song,
      file,
      cancelled: cancelled,
      progress: progress,
    ),
    keepResultOnCancel: true,
  );
  return applied == true ? '已为「${song.title ?? song.name}」关联新文件。' : null;
});

Future<void> _run(
  BuildContext context,
  LibraryController library,
  Future<String?> Function(LibraryRelocation) work,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  String? status;
  try {
    await library.runRelocation((relocation) async {
      status = await work(relocation);
    });
  } on StateError catch (error) {
    status = error.message;
  } on FileSystemException catch (error) {
    status = error.message;
  } on PlatformException catch (error) {
    status = error.message ?? '无法读取所选目录。';
  } catch (error, stack) {
    debugPrint('重新定位失败 $error\n$stack');
    status = '操作失败，请检查目录访问权限和可用空间。';
  }
  if (status != null && messenger?.mounted == true) {
    messenger!.showSnackBar(SnackBar(content: Text(status!)));
  }
}

Future<T?> _inspect<T>(
  BuildContext context,
  LibraryController library,
  String title,
  Future<T> Function(Cancelled, RelocationProgress) work, {
  bool keepResultOnCancel = false,
}) async {
  final result =
      await showDialog<({T? value, Object? error, StackTrace? stack})>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _Inspection(
          title: title,
          work: work,
          cancelHash: library.documents.cancelMusicHash,
          keepResultOnCancel: keepResultOnCancel,
        ),
      );
  if (result?.error case final error?) {
    Error.throwWithStackTrace(error, result!.stack!);
  }
  return result?.value;
}

class _Inspection<T> extends StatefulWidget {
  const _Inspection({
    required this.title,
    required this.work,
    required this.cancelHash,
    required this.keepResultOnCancel,
  });

  final String title;
  final Future<T> Function(Cancelled, RelocationProgress) work;
  final Future<void> Function() cancelHash;
  final bool keepResultOnCancel;

  @override
  State<_Inspection<T>> createState() => _InspectionState<T>();
}

class _InspectionState<T> extends State<_Inspection<T>> {
  bool _cancelled = false;
  int _processed = 0;
  Future<void>? _cancelTask;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    T? value;
    Object? failure;
    StackTrace? stack;
    try {
      value = await widget.work(() => _cancelled || !mounted, (count) {
        if (mounted) setState(() => _processed = count);
      });
    } catch (error, trace) {
      failure = error;
      stack = trace;
    }
    await _cancelTask;
    if (!mounted) return;
    final discard = _cancelled && !widget.keepResultOnCancel;
    Navigator.pop(context, (
      value: discard ? null : value,
      error: discard ? null : failure,
      stack: stack,
    ));
  }

  Future<void> _stopHash() async {
    try {
      await widget.cancelHash();
    } catch (e) {
      debugPrint('取消文件指纹计算：$e');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: CompactAlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(_cancelled ? '正在取消…' : '已处理 $_processed 项'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _cancelled
              ? null
              : () {
                  setState(() => _cancelled = true);
                  _cancelTask = _stopHash();
                },
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

class _DirectoryPreview extends StatelessWidget {
  const _DirectoryPreview(this.plan);
  final DirectoryRelocation plan;

  @override
  Widget build(BuildContext context) {
    final count = plan.matches.length;
    final missing = plan.unmatched.length;
    return CompactAlertDialog(
      title: const Text('目录重新定位预览'),
      content: SizedBox(
        width: 500,
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('可关联 $count 首 · 未匹配 $missing 首'),
            Text(
              count == 0
                  ? '请核对目录，或到歌曲列表逐首关联。'
                  : '确认后，匹配的歌曲会沿用原有标签和歌单。未匹配的记录会保留。',
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: count + missing,
                itemBuilder: (context, index) {
                  if (index >= count) {
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.link_off),
                      title: Text(plan.unmatched[index - count].relativePath),
                      subtitle: const Text('待手动关联'),
                    );
                  }
                  final match = plan.matches[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.link),
                    title: Text(match.song.title ?? match.song.name),
                    subtitle: Text(
                      '${match.file.relativePath}\n${match.reason}',
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: count == 0 ? null : () => Navigator.pop(context, true),
          child: const Text('关联歌曲'),
        ),
      ],
    );
  }
}

class _SongPicker extends StatefulWidget {
  const _SongPicker({
    required this.song,
    required this.files,
    required this.occupied,
  });
  final Song song;
  final List<ScannedFile> files;
  final Set<String> occupied;

  @override
  State<_SongPicker> createState() => _SongPickerState();
}

class _SongPickerState extends State<_SongPicker> {
  String _query = '';
  ScannedFile? _selected;

  @override
  Widget build(BuildContext context) {
    final files = widget.files
        .where((file) => file.relativePath.toLowerCase().contains(_query))
        .toList();
    return CompactAlertDialog(
      title: const Text('选择要关联的文件'),
      content: SizedBox(
        width: 500,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('原歌曲：${widget.song.title ?? widget.song.name}'),
            TextField(
              decoration: const InputDecoration(labelText: '搜索文件名或子目录'),
              onChanged: (text) => setState(() {
                _query = text.trim().toLowerCase();
                _selected = null;
              }),
            ),
            Expanded(
              child: files.isEmpty
                  ? const Center(child: Text('没有匹配的文件'))
                  : ListView.builder(
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final occupied = widget.occupied.contains(
                          file.identity,
                        );
                        return ListTile(
                          dense: true,
                          enabled: !occupied,
                          selected: _selected == file,
                          title: Text(file.relativePath),
                          subtitle: occupied ? const Text('已关联到另一条歌曲记录') : null,
                          trailing: _selected == file
                              ? const Icon(Icons.check)
                              : null,
                          onTap: occupied
                              ? null
                              : () => setState(() => _selected = file),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('关联文件'),
        ),
      ],
    );
  }
}
