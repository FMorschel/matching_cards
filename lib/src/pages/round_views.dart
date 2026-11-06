import 'package:flutter/material.dart';
import 'package:matching_cards_core/matching_cards_core.dart';

import '../session.dart';
import '../widgets/cards.dart';

Widget _constrained(Widget child) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: child,
      ),
    );

String _nameOf(GameView view, String? id) => view.playerById(id)?.name ?? 'Someone';

/// The Card Czar waits while the others choose.
class CzarWaitingView extends StatelessWidget {
  const CzarWaitingView({super.key, required this.session, required this.view});

  final GameSession session;
  final GameView view;

  @override
  Widget build(BuildContext context) {
    final round = view.round!;
    return _constrained(
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Round ${round.number} · You are the Card Czar',
              style: Theme.of(context).textTheme.titleMedium),
          PromptCard(prompt: round.prompt),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: round.expectedCount == 0
                ? 0
                : round.submittedCount / round.expectedCount,
          ),
          const SizedBox(height: 8),
          Text('${round.submittedCount} of ${round.expectedCount} answers in'),
          const SizedBox(height: 16),
          for (final p in view.players.where((p) => !p.isCzar))
            ListTile(
              dense: true,
              leading: Icon(p.hasSubmitted ? Icons.check_circle : Icons.hourglass_empty),
              title: Text(p.name),
            ),
        ],
      ),
    );
  }
}

/// A player chooses [RoundView.pick] answers from their hand.
class PickingView extends StatefulWidget {
  const PickingView({super.key, required this.session, required this.view});

  final GameSession session;
  final GameView view;

  @override
  State<PickingView> createState() => _PickingViewState();
}

class _PickingViewState extends State<PickingView> {
  final List<int> _chosen = [];
  int? _round;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final round = view.round!;
    if (_round != round.number) {
      _round = round.number;
      _chosen.clear();
    }
    final you = view.you;

    return _constrained(
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Round ${round.number} · ${_nameOf(view, round.czarId)} is the Card Czar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          PromptCard(
            prompt: round.prompt,
            answers: you.hasSubmitted
                ? you.submitted
                : [
                    for (final id in _chosen)
                      you.hand.firstWhere((c) => c.id == id).text,
                  ],
          ),
          if (you.hasSubmitted) ...[
            const SizedBox(height: 12),
            Text(
              'Answer sent. ${round.submittedCount} of ${round.expectedCount} in.',
              textAlign: TextAlign.center,
            ),
          ] else if (!you.canPlay) ...[
            const SizedBox(height: 12),
            const Text(
              'You joined mid-round. You will play in the next one.',
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              round.pick > 1
                  ? 'Choose ${round.pick} answers, in order.'
                  : 'Choose an answer.',
            ),
            for (final card in you.hand)
              AnswerCard(
                text: card.text,
                selected: _chosen.contains(card.id),
                order: _chosen.contains(card.id) && round.pick > 1
                    ? _chosen.indexOf(card.id) + 1
                    : null,
                onTap: () => setState(() {
                  if (_chosen.contains(card.id)) {
                    _chosen.remove(card.id);
                  } else if (round.pick == 1) {
                    _chosen
                      ..clear()
                      ..add(card.id);
                  } else if (_chosen.length < round.pick) {
                    _chosen.add(card.id);
                  }
                }),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _chosen.length == round.pick
                  ? () => widget.session.submit(List.of(_chosen))
                  : null,
              child: const Text('Play'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Czar picks a favourite; everyone else watches.
class JudgingView extends StatelessWidget {
  const JudgingView({super.key, required this.session, required this.view});

  final GameSession session;
  final GameView view;

  @override
  Widget build(BuildContext context) {
    final round = view.round!;
    final isCzar = view.you.isCzar;
    return _constrained(
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            isCzar
                ? 'Pick the best one'
                : '${_nameOf(view, round.czarId)} is choosing…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final s in round.submissions)
            SubmissionCard(
              prompt: round.prompt,
              submission: s,
              onTap: isCzar ? () => _confirm(context, s) : null,
            ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, SubmissionView s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose this one?'),
        content: Text(fillBlanks(view.round!.prompt, s.answers)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (ok == true) session.pick(s.id);
  }
}

class RoundEndView extends StatelessWidget {
  const RoundEndView({super.key, required this.session, required this.view});

  final GameSession session;
  final GameView view;

  @override
  Widget build(BuildContext context) {
    final round = view.round!;
    final canContinue = view.you.isHost || view.you.isCzar;
    return _constrained(
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${_nameOf(view, round.winnerId)} wins the round',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final s in round.submissions)
            SubmissionCard(
              prompt: round.prompt,
              submission: s,
              author: _nameOf(view, s.playerId),
              highlight: s.isWinner,
            ),
          const SizedBox(height: 8),
          if (canContinue)
            FilledButton(onPressed: session.next, child: const Text('Next round'))
          else
            const Text('Waiting for the host or the Czar…', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Scoreboard(view: view),
        ],
      ),
    );
  }
}

class GameOverView extends StatelessWidget {
  const GameOverView({super.key, required this.session, required this.view});

  final GameSession session;
  final GameView view;

  @override
  Widget build(BuildContext context) {
    final top = [...view.players]..sort((a, b) => b.score.compareTo(a.score));
    final winner = top.isEmpty ? null : top.first;
    return _constrained(
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            winner == null ? 'Game over' : '🏆 ${winner.name} wins!',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Scoreboard(view: view),
          const SizedBox(height: 16),
          if (view.you.isHost)
            FilledButton(onPressed: session.playAgain, child: const Text('Play again'))
          else
            const Text('The host can start another game.', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
