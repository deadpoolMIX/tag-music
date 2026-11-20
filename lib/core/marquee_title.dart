import 'package:flutter/material.dart';

class MarqueeTitle extends StatelessWidget {
  const MarqueeTitle({
    required this.text,
    required this.style,
    this.pause = Duration.zero,
    super.key,
  });
  final String text;
  final TextStyle style;
  final Duration pause;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      if (MediaQuery.disableAnimationsOf(context) ||
          constraints.maxWidth <= 0) {
        return title;
      }
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        locale: Localizations.maybeLocaleOf(context),
        maxLines: 1,
      )..layout();
      final titleWidth = painter.width;
      final titleHeight = painter.height;
      painter.dispose();
      return titleWidth <= constraints.maxWidth
          ? title
          : SizedBox(
              height: titleHeight,
              child: _MarqueeTitle(
                key: ValueKey((text, titleWidth, constraints.maxWidth)),
                text: text,
                style: style,
                distance: titleWidth + 40,
                pause: pause,
              ),
            );
    },
  );
}

class _MarqueeTitle extends StatefulWidget {
  const _MarqueeTitle({
    required this.text,
    required this.style,
    required this.distance,
    required this.pause,
    super.key,
  });

  final String text;
  final TextStyle style;
  final double distance;
  final Duration pause;

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _offset;

  @override
  void initState() {
    super.initState();
    final pause = widget.pause.inMilliseconds.toDouble();
    final travel = widget.distance / 34 * 1000;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (pause + travel).round()),
    )..repeat();
    _offset = TweenSequence<double>([
      if (pause > 0)
        TweenSequenceItem(tween: ConstantTween(0.0), weight: pause),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: widget.distance),
        weight: travel,
      ),
    ]).animate(_controller);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.text,
    excludeSemantics: true,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: AnimatedBuilder(
          animation: _offset,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 40,
            children: [
              Text(widget.text, style: widget.style, maxLines: 1),
              Text(widget.text, style: widget.style, maxLines: 1),
            ],
          ),
          builder: (_, child) => Transform.translate(
            offset: Offset(-_offset.value, 0),
            child: child,
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
