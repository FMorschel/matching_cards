import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matching_cards_core/matching_cards_core.dart';

import '../lan_host.dart';
import '../session.dart';
import '../widgets/cards.dart';
import 'lobby_view.dart';
import 'round_views.dart';

/// Everything after joining: follows the session and shows the right view.
class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.session, this.host});

  final GameSession session;

  /// Set when this device is hosting.
  final LanHost? host;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  StreamSubscription<String>? _errors;

  @override
  void initState() {
    super.initState();
    _errors = widget.session.errors.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    widget.session.dispose();
    widget.host?.stop();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final hosting = widget.host != null;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(hosting ? 'Stop hosting?' : 'Leave the game?'),
        content: Text(
          hosting
              ? 'The game ends for everyone connected to you.'
              : 'You can rejoin later and keep your seat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(hosting ? 'Stop' : 'Leave'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: ListenableBuilder(
        listenable: widget.session,
        builder: (context, _) {
          final session = widget.session;
          final view = session.view;
          return Scaffold(
            appBar: AppBar(
              title: Text(view?.gameName ?? 'Matching Cards'),
              actions: [
                if (view != null)
                  IconButton(
                    tooltip: 'Scores',
                    icon: const Icon(Icons.leaderboard),
                    onPressed: () => _showScores(view),
                  ),
                IconButton(
                  tooltip: 'Leave',
                  icon: const Icon(Icons.exit_to_app),
                  onPressed: _confirmLeave,
                ),
              ],
            ),
            body: SafeArea(child: _body(session, view)),
          );
        },
      ),
    );
  }

  Widget _body(GameSession session, GameView? view) {
    if (session.status == SessionStatus.closed ||
        session.status == SessionStatus.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48),
              const SizedBox(height: 12),
              Text(session.failure ?? 'Disconnected.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }
    if (view == null) return const Center(child: CircularProgressIndicator());

    final Widget content;
    switch (view.phase) {
      case Phase.lobby:
        content = LobbyView(session: session, view: view, host: widget.host);
      case Phase.picking:
        content = view.you.isCzar
            ? CzarWaitingView(session: session, view: view)
            : PickingView(session: session, view: view);
      case Phase.judging:
        content = JudgingView(session: session, view: view);
      case Phase.roundEnd:
        content = RoundEndView(session: session, view: view);
      case Phase.gameOver:
        content = GameOverView(session: session, view: view);
    }
    return Column(
      children: [
        if (view.notice != null)
          MaterialBanner(
            content: Text(view.notice!),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(child: content),
      ],
    );
  }

  void _showScores(GameView view) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(child: SingleChildScrollView(child: Scoreboard(view: view))),
    );
  }
}
