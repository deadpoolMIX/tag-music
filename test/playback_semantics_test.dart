import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tag_music/app.dart';
import 'package:tag_music/library/database.dart';
import 'package:tag_music/library/library_controller.dart';
import 'package:tag_music/playback/playback_controller.dart';

import 'library_page_test.dart' as playback_test;
import 'library_test.dart' show FakeDocuments, entry;

class _TreeRecordingBinding extends AutomatedTestWidgetsFlutterBinding {
  final nodes = <int, List<int>>{};
  final errors = <String>[];
  final submitted = <int>{};
  final previousNodes = <int, List<int>>{};

  @override
  ui.SemanticsUpdateBuilder createSemanticsUpdateBuilder() =>
      _RecordingBuilder(this);

  void finishFrame() {
    // The native bridge removes reparented subtrees before applying updates.
    // A final merged framework tree can therefore look connected even when a
    // descendant destroyed by that removal was not serialized again.
    final previousParents = <int, int>{};
    for (final entry in previousNodes.entries) {
      for (final child in entry.value) {
        previousParents[child] = entry.key;
      }
    }
    final removed = <int>{};
    void removeSubtree(int id) {
      if (!removed.add(id)) return;
      for (final child in previousNodes[id] ?? const <int>[]) {
        removeSubtree(child);
      }
    }

    for (final id in submitted) {
      final children = nodes[id] ?? const <int>[];
      for (final oldChild in previousNodes[id] ?? const <int>[]) {
        if (!children.contains(oldChild)) removeSubtree(oldChild);
      }
      for (final child in children) {
        if (previousParents.containsKey(child) &&
            previousParents[child] != id) {
          removeSubtree(child);
        }
      }
    }
    final reachable = <int>{};
    void visit(int id) {
      if (!reachable.add(id)) return;
      for (final child in nodes[id] ?? const <int>[]) {
        visit(child);
      }
    }

    visit(0);
    final missingAfterRemoval = reachable
        .intersection(removed)
        .difference(submitted);
    if (missingAfterRemoval.isNotEmpty) {
      errors.add(
        'Native subtree removal loses unsubmitted nodes: $missingAfterRemoval',
      );
    }
    final missing = <int>{};
    for (final id in reachable) {
      if (!nodes.containsKey(id)) missing.add(id);
    }
    if (missing.isNotEmpty) {
      errors.add('Serialized missing child semantics nodes: $missing');
    }
    final orphaned = submitted.difference(reachable);
    if (orphaned.isNotEmpty) {
      errors.add('Serialized orphan semantics nodes: $orphaned');
    }
    nodes.removeWhere((id, _) => !reachable.contains(id));
    previousNodes
      ..clear()
      ..addAll(
        nodes.map((id, children) => MapEntry(id, List<int>.of(children))),
      );
    submitted.clear();
  }
}

// Capture the actual serialized updates, rather than only the framework tree.
// The native AXTree rejects incoming nodes not connected to its root.
class _RecordingBuilder extends Fake implements ui.SemanticsUpdateBuilder {
  _RecordingBuilder(this.binding);
  final _TreeRecordingBinding binding;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #updateNode) {
      final args = invocation.namedArguments;
      final id = args[#id] as int;
      binding.nodes[id] = List<int>.from(
        args[#childrenInTraversalOrder] as Iterable<int>,
      );
      binding.submitted.add(id);
      return null;
    }
    if (invocation.memberName == #updateCustomAction) return null;
    return super.noSuchMethod(invocation);
  }

  @override
  ui.SemanticsUpdate build() {
    binding.finishFrame();
    return ui.SemanticsUpdateBuilder().build();
  }
}

void main() {
  final binding = _TreeRecordingBinding();

  setUp(() {
    binding.nodes.clear();
    binding.errors.clear();
    binding.submitted.clear();
    binding.previousNodes.clear();
  });

  test('reparent replay accepts descendants that are submitted again', () {
    binding.nodes.addAll({
      0: [1],
      1: [2],
      2: [3],
      3: [],
    });
    binding.submitted.addAll(binding.nodes.keys);
    binding.finishFrame();
    binding.nodes.addAll({
      0: [1, 4],
      1: [],
      4: [2],
      2: [3],
      3: [],
    });
    binding.submitted.addAll([0, 1, 4, 2, 3]);
    binding.finishFrame();
    expect(binding.errors, isEmpty);
  });

  test('reparent replay detects descendants omitted after subtree removal', () {
    binding.nodes.addAll({
      0: [1],
      1: [2],
      2: [3],
      3: [],
    });
    binding.submitted.addAll(binding.nodes.keys);
    binding.finishFrame();
    expect(binding.errors, isEmpty);
    binding.nodes.addAll({
      0: [1, 4],
      1: [],
      4: [2],
      2: [3],
    });
    binding.submitted.addAll([0, 1, 4, 2]);
    binding.finishFrame();
    expect(binding.errors, [
      'Native subtree removal loses unsubmitted nodes: {3}',
    ]);
  });

  testWidgets(
    'seek availability changes preserve the Windows semantics subtree',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = FakeDocuments()
        ..files['root'] = List.generate(9, (index) => entry(index.toString()));
      final library = LibraryController(
        LibraryDatabase(NativeDatabase.memory()),
        access,
      );
      await tester.runAsync(() async {
        await library.initialize();
        await library.scan();
      });
      final playback = playback_test.SnapshotController()..current = null;
      playback.player.state = playback.player.state.copyWith(
        duration: Duration.zero,
        playing: false,
      );
      final semantics = tester.ensureSemantics();
      binding.nodes.clear();
      binding.errors.clear();
      binding.submitted.clear();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryProvider.overrideWithValue(library),
            playbackProvider.overrideWithValue(playback),
          ],
          child: const TagMusicApp(),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      final songPoint = tester.getCenter(find.text('歌曲 0.mp3'));
      await mouse.addPointer(location: songPoint);
      await mouse.down(songPoint);
      await mouse.up();
      await tester.pump();
      playback.emit(
        playback.player.state.copyWith(
          duration: const Duration(seconds: 24),
          playing: true,
        ),
      );
      await tester.pumpAndSettle();
      // Stopping and starting another stream crosses the same boundary again.
      playback.emit(
        playback.player.state.copyWith(duration: Duration.zero, playing: false),
      );
      await tester.pumpAndSettle();
      playback.emit(
        playback.player.state.copyWith(
          duration: const Duration(seconds: 24),
          playing: true,
        ),
      );
      await tester.pumpAndSettle();
      await mouse.removePointer();
      final errors = List.of(binding.errors);
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
      playback.dispose();
      await tester.runAsync(library.shutdown);
      expect(
        errors,
        isEmpty,
        reason: 'Changing seek availability must resend descendants removed during reparenting.',
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}
