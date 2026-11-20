import 'package:flutter/material.dart';

class CompactAlertDialog extends AlertDialog {
  const CompactAlertDialog({
    super.title,
    super.content,
    super.actions,
    super.scrollable,
    super.key,
  }) : super(
         titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
         contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
         actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
       );
}
