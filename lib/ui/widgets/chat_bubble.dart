import 'package:flutter/services.dart';
import '../stitch_style.dart';
import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/friday_response.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    this.source,
    this.isPartial = false,
  });

  final ChatMessage message;
  final FridaySource? source;
  final bool isPartial;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final sourceLabel = switch (source) {
      FridaySource.cloud => 'cloud',
      FridaySource.local => 'on-device',
      FridaySource.offline => 'offline',
      null => '',
    };

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.82 : 0.92),
        ),
        decoration: BoxDecoration(
          color: isUser ? Stitch.high : Stitch.low,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isUser) ...[
              Row(children: [
                const Icon(Icons.receipt_long, color: Stitch.cyan, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('FRIDAY RESPONSE',
                        style: Stitch.mono(11, Stitch.cyan))),
                const StitchBadge('RESULT')
              ]),
              const SizedBox(height: 14)
            ],
            Text(
              isPartial ? '${message.text}...' : message.text,
              style: theme.textTheme.bodyMedium,
            ),
            if (!isUser) ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                    child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Stitch.high,
                            borderRadius: BorderRadius.circular(12)),
                        child: Text('Recorded reply · check the result details',
                            style: Stitch.mono(9)))),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                    tooltip: 'Copy response',
                    onPressed: () async {
                      await Clipboard.setData(
                          ClipboardData(text: message.text));
                    },
                    icon: const Icon(Icons.copy, size: 18))
              ])
            ],
            if (!isUser && sourceLabel.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                sourceLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
