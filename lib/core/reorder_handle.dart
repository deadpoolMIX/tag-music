import 'package:flutter/material.dart';

class ReorderHandle extends StatelessWidget {
  const ReorderHandle({
    required this.index,
    required this.label,
    this.enabled = true,
    super.key,
  });

  final int index;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: index,
    enabled: enabled,
    child: Tooltip(
      message: label,
      // A long-press tooltip otherwise wins the gesture before the user moves.
      triggerMode: TooltipTriggerMode.manual,
      child: Container(
        width: 48,
        height: 48,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: const Icon(Icons.drag_handle),
      ),
    ),
  );
}
