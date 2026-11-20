import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shares the active list's selection mode with the app chrome.
class SongSelectionController extends ChangeNotifier {
  Object? _owner;
  bool _notificationPending = false;

  bool get isSelecting => _owner != null;

  void begin(Object owner) => _setOwner(owner);

  void end(Object owner) {
    if (identical(_owner, owner)) _setOwner(null);
  }

  void _setOwner(Object? owner) {
    final wasSelecting = isSelecting;
    _owner = owner;
    if (wasSelecting == isSelecting || _notificationPending) return;
    final scheduler = SchedulerBinding.instance;
    if (scheduler.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    // An inactive or removed list can end selection during layout or disposal.
    _notificationPending = true;
    scheduler.addPostFrameCallback((_) {
      if (!_notificationPending) return;
      _notificationPending = false;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _notificationPending = false;
    super.dispose();
  }
}

class SongSelectionScope extends InheritedNotifier<SongSelectionController> {
  const SongSelectionScope({
    required super.notifier,
    required super.child,
    super.key,
  });

  static SongSelectionController? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SongSelectionScope>()?.notifier;

  static bool isSelectingOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SongSelectionScope>()
          ?.notifier
          ?.isSelecting ??
      false;
}
