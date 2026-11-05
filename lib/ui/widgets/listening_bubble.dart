import 'package:flutter/material.dart';
import '../stitch_style.dart';

/// Ephemeral user-side speech draft. Never persisted or submitted by this widget.
class ListeningBubble extends StatelessWidget {
  const ListeningBubble({super.key, required this.text, this.compact = false});
  final String text;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
        liveRegion: true,
        label: text.isEmpty ? 'Listening' : 'You are saying: $text',
        child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              key: const ValueKey('voice-draft-bubble'),
              margin: EdgeInsets.symmetric(
                  horizontal: compact ? 16 : 20, vertical: 8),
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 12 : 16, vertical: compact ? 10 : 16),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * .82),
              decoration: BoxDecoration(
                  color: compact ? cs.primaryContainer : Stitch.high,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4))),
              child: text.isEmpty
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Listening',
                          style: TextStyle(
                              fontSize: compact ? 13 : null,
                              color: compact
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface)),
                      const SizedBox(width: 12),
                      for (int i = 0; i < 3; i++)
                        Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                    color: Stitch.cyan,
                                    shape: BoxShape.circle)))
                    ])
                  : Text.rich(
                      TextSpan(children: [
                        TextSpan(text: text),
                        WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Container(
                                    width: 2,
                                    height: compact ? 14 : 17,
                                    color: Stitch.cyan)))
                      ]),
                      style: TextStyle(
                          fontSize: compact ? 13 : null,
                          color:
                              compact ? cs.onPrimaryContainer : cs.onSurface)),
            )));
  }
}
