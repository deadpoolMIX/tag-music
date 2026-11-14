import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'library_controller.dart';

Future<void> showSongInformation(BuildContext context, LibraryTrack track) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SongInformationDialog(track: track),
    );

class _SongInformationDialog extends StatefulWidget {
  const _SongInformationDialog({required this.track});
  final LibraryTrack track;
  @override
  State<_SongInformationDialog> createState() => _SongInformationDialogState();
}

class _SongInformationDialogState extends State<_SongInformationDialog> {
  bool _copying = false;
  String? _copyResult;

  String _known(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? '未知' : text;
  }

  String _duration(int? milliseconds) {
    if (milliseconds == null || milliseconds < 0) return '未知';
    final seconds = milliseconds ~/ 1000;
    final hours = seconds ~/ 3600;
    final minutes = seconds ~/ 60 % 60;
    return '${hours > 0 ? '$hours:' : ''}${hours > 0 ? '$minutes'.padLeft(2, '0') : minutes}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _size(int? bytes) {
    if (bytes == null || bytes < 0) return '未知';
    const units = ['字节', 'KiB', 'MiB', 'GiB', 'TiB'];
    var amount = bytes.toDouble(), unit = 0;
    while (amount >= 1024 && unit < units.length - 1) {
      amount /= 1024;
      unit++;
    }
    return unit == 0
        ? '$bytes 字节'
        : '${amount.toStringAsFixed(2)} ${units[unit]}（$bytes 字节）';
  }

  String _modified(int? milliseconds) {
    if (milliseconds == null) return '未知';
    try {
      final date = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
      String two(int value) => '$value'.padLeft(2, '0');
      return '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}:${two(date.second)}（本地时间）';
    } on ArgumentError {
      return '未知';
    }
  }

  Map<String, String> get _metadata {
    final song = widget.track.song;
    return {
      '歌名': _known(song.title),
      '歌手': _known(song.artist),
      '专辑': _known(song.album),
      '时长': _duration(song.durationMs),
    };
  }

  Map<String, String> get _file {
    final song = widget.track.song;
    final dot = song.name.lastIndexOf('.');
    return {
      '文件名': _known(song.name),
      '格式': dot > 0 && dot < song.name.length - 1
          ? song.name.substring(dot + 1).toUpperCase()
          : '未知',
      '大小': _size(song.size),
      '修改时间': _modified(song.modified),
      '可用状态': widget.track.available ? '可用' : '文件失联或目录不可访问',
    };
  }

  Future<void> _copy() async {
    if (_copying) return;
    setState(() {
      _copying = true;
      _copyResult = null;
    });
    try {
      await Clipboard.setData(
        ClipboardData(
          text: {
            ..._metadata,
            ..._file,
          }.entries.map((e) => '${e.key}：${e.value}').join('\n'),
        ),
      );
      if (mounted) setState(() => _copyResult = '已复制全部歌曲信息');
    } catch (_) {
      if (mounted) setState(() => _copyResult = '复制失败，可长按或选中文字后复制。');
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Widget _section(String title, Map<String, String> fields) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.titleSmall),
      ),
      const SizedBox(height: 12),
      for (final field in fields.entries) ...[
        Text(
          field.key,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(field.value),
        const SizedBox(height: 16),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('歌曲信息 · 只读'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('信息来自曲库记录，仅供查看，不修改音乐文件。'),
            const SizedBox(height: 20),
            SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _section('歌曲资料', _metadata),
                  const Divider(),
                  const SizedBox(height: 12),
                  _section('文件资料', _file),
                ],
              ),
            ),
            if (_copyResult case final result?)
              Semantics(liveRegion: true, child: Text(result)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: _copying ? null : _copy,
        icon: const Icon(Icons.copy),
        label: const Text('复制全部信息'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  );
}
