import 'dart:async';

import 'package:flutter/material.dart';
import 'package:matching_cards_core/matching_cards_core.dart';

import '../lan_discovery.dart';

/// Lists games found on the network and takes a typed address. Pops with the
/// WebSocket address to join.
class JoinPage extends StatefulWidget {
  const JoinPage({super.key});

  @override
  State<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends State<JoinPage> {
  final _address = TextEditingController();
  StreamSubscription<List<DiscoveredGame>>? _subscription;
  List<DiscoveredGame> _games = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (lanScanSupported) {
      _subscription = findLanGames().listen((games) {
        if (mounted) setState(() => _games = games);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final uri = parseGameAddress(_address.text);
    if (uri == null) {
      setState(() => _error = 'That does not look like an address.');
      return;
    }
    Navigator.of(context).pop(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join a game')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (lanScanSupported) ...[
            Text('On your network', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_games.isEmpty)
              const ListTile(
                leading: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Looking for games…'),
                subtitle: Text(
                  'A host has to press "I want others to join in".',
                ),
              ),
            for (final game in _games)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(game.name),
                  subtitle: Text(
                    '${game.host}:${game.port} · ${game.players} playing',
                  ),
                  onTap: () => Navigator.of(context).pop(game.webSocketUri),
                ),
              ),
            const Divider(height: 32),
          ] else ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Browsers cannot search the network. Ask the host for the '
                'address (or scan their QR code) and type it here.',
              ),
            ),
          ],
          Text('By address', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _address,
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Host address',
              hintText: '192.168.1.20:8080',
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _submit, child: const Text('Join')),
        ],
      ),
    );
  }
}
