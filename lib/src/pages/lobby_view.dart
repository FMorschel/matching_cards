import 'package:flutter/material.dart';
import 'package:matching_cards_core/matching_cards_core.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../lan_host.dart';
import '../session.dart';

class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.session, required this.view, this.host});

  final GameSession session;
  final GameView view;
  final LanHost? host;

  @override
  Widget build(BuildContext context) {
    final isHost = view.you.isHost;
    final enough = view.connectedCount >= view.minPlayers;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (host != null) InvitePanel(host: host!),
            Text(
              view.started ? 'Game paused' : 'Waiting for players',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              enough
                  ? 'Ready when you are.'
                  : 'Needs at least ${view.minPlayers} players '
                      '(${view.connectedCount} here).',
            ),
            const SizedBox(height: 8),
            for (final p in view.players)
              ListTile(
                dense: true,
                leading: Icon(p.connected ? Icons.person : Icons.person_off_outlined),
                title: Text(p.name + (p.id == view.you.id ? ' (you)' : '')),
                subtitle: p.isHost ? const Text('host') : null,
                trailing: isHost && p.id != view.you.id
                    ? IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.close),
                        onPressed: () => session.kick(p.id),
                      )
                    : null,
              ),
            const Divider(height: 32),
            if (isHost && !view.started) ..._settings(context) else if (!view.started)
              _readOnlySettings(context),
            const SizedBox(height: 16),
            if (isHost)
              FilledButton.icon(
                onPressed: enough ? session.start : null,
                icon: const Icon(Icons.play_arrow),
                label: Text(view.started ? 'Resume' : 'Start game'),
              )
            else
              const Text('The host starts the game.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _readOnlySettings(BuildContext context) {
    final c = view.config;
    return Text(
      'First to ${c.pointsToWin} points · ${c.handSize} cards in hand · '
      '${c.categories.length} categories',
    );
  }

  List<Widget> _settings(BuildContext context) {
    final config = view.config;
    return [
      Text('Settings', style: Theme.of(context).textTheme.titleMedium),
      _Stepper(
        label: 'Points to win',
        value: config.pointsToWin,
        min: GameConfig.minPoints,
        max: GameConfig.maxPoints,
        onChanged: (v) => session.setConfig(config.copyWith(pointsToWin: v)),
      ),
      _Stepper(
        label: 'Cards in hand',
        value: config.handSize,
        min: GameConfig.minHandSize,
        max: GameConfig.maxHandSize,
        onChanged: (v) => session.setConfig(config.copyWith(handSize: v)),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text('Categories', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          TextButton(
            onPressed: () => session.setConfig(
              config.copyWith(categories: [for (final d in view.decks) d.name]),
            ),
            child: const Text('All'),
          ),
          TextButton(
            onPressed: () => session.setConfig(config.copyWith(categories: const [])),
            child: const Text('None'),
          ),
        ],
      ),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final deck in view.decks)
            FilterChip(
              label: Text(deck.name),
              selected: config.categories.contains(deck.name),
              onSelected: (on) {
                final next = [...config.categories];
                on ? next.add(deck.name) : next.remove(deck.name);
                session.setConfig(config.copyWith(categories: next));
              },
            ),
        ],
      ),
    ];
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

/// The host's "I want others to join in" switch, with how to join.
class InvitePanel extends StatefulWidget {
  const InvitePanel({super.key, required this.host});

  final LanHost host;

  @override
  State<InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<InvitePanel> {
  bool _busy = false;

  Future<void> _toggle(bool open) async {
    setState(() => _busy = true);
    await widget.host.setOpen(open);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.host;
    if (!host.isOpen) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Right now only this device can see the game.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : () => _toggle(true),
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('I want others to join in'),
              ),
            ],
          ),
        ),
      );
    }

    final urls = [for (final a in host.addresses) 'http://$a:${host.port}'];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi_tethering),
                const SizedBox(width: 8),
                Text('Visible on your network', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'App users find this game under "Join a game". Anyone else can '
              'open an address below in a browser.',
            ),
            if (!host.webClientBundled)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'This build has no web client bundled, so browsers cannot join. '
                  'See the README (tool/bundle_web.dart).',
                ),
              ),
            const SizedBox(height: 8),
            if (urls.isEmpty) const Text('No network address found.'),
            for (final url in urls) SelectableText(url),
            if (urls.isNotEmpty && host.webClientBundled)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: QrImageView(
                    data: urls.first,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _toggle(false),
              child: const Text('Stop sharing'),
            ),
          ],
        ),
      ),
    );
  }
}
