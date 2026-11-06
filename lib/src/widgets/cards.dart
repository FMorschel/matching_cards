import 'package:flutter/material.dart';
import 'package:matching_cards_core/matching_cards_core.dart';

/// The black prompt card. Blanks are filled with [answers] (underlined) when
/// given, and left as a gap otherwise.
class PromptCard extends StatelessWidget {
  const PromptCard({super.key, required this.prompt, this.answers = const []});

  final String prompt;
  final List<String> answers;

  @override
  Widget build(BuildContext context) {
    final parts = prompt.split(blankToken);
    final spans = <InlineSpan>[];
    for (var i = 0; i < parts.length; i++) {
      spans.add(TextSpan(text: parts[i]));
      if (i < parts.length - 1) {
        spans.add(
          i < answers.length
              ? TextSpan(
                  text: answers[i],
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w800,
                    color: Colors.amberAccent,
                  ),
                )
              : const TextSpan(
                  text: '_____',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        );
      }
    }
    return Card(
      color: const Color(0xFF15151C),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text.rich(
          TextSpan(children: spans),
          style: const TextStyle(color: Colors.white, fontSize: 22, height: 1.3),
        ),
      ),
    );
  }
}

/// A white answer card.
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    super.key,
    required this.text,
    this.selected = false,
    this.order,
    this.onTap,
    this.highlight = false,
  });

  final String text;
  final bool selected;

  /// 1, 2, ... when several cards must be chosen.
  final int? order;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected || highlight ? scheme.primary : Colors.black12,
          width: selected || highlight ? 3 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (order != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: CircleAvatar(radius: 14, child: Text('$order')),
                ),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One anonymous (or revealed) submission: the prompt filled in with it.
class SubmissionCard extends StatelessWidget {
  const SubmissionCard({
    super.key,
    required this.prompt,
    required this.submission,
    this.author,
    this.onTap,
    this.highlight = false,
  });

  final String prompt;
  final SubmissionView submission;
  final String? author;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlight ? scheme.primary : Colors.transparent,
          width: 3,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PromptCard(prompt: prompt, answers: submission.answers),
            if (author != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '${submission.isWinner ? '🏆 ' : ''}$author',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class Scoreboard extends StatelessWidget {
  const Scoreboard({super.key, required this.view});

  final GameView view;

  @override
  Widget build(BuildContext context) {
    final players = [...view.players]..sort((a, b) => b.score.compareTo(a.score));
    return Column(
      children: [
        for (final p in players)
          ListTile(
            dense: true,
            leading: Icon(
              p.connected ? Icons.person : Icons.person_off_outlined,
              color: p.connected ? null : Theme.of(context).disabledColor,
            ),
            title: Text(
              p.name + (p.id == view.you.id ? ' (you)' : ''),
              style: TextStyle(fontWeight: p.isCzar ? FontWeight.bold : null),
            ),
            subtitle: Text(
              [
                if (p.isHost) 'host',
                if (p.isCzar) 'Card Czar',
                if (!p.connected) 'away',
              ].join(' · '),
            ),
            trailing: Text('${p.score}', style: Theme.of(context).textTheme.titleLarge),
          ),
      ],
    );
  }
}
