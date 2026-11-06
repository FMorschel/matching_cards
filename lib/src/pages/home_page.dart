import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:matching_cards_core/matching_cards_core.dart';

import '../lan_host.dart';
import '../session.dart';
import '../storage.dart';
import 'game_page.dart';
import 'join_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;

  /// When the web client is served by a host, that host is right here.
  Uri? get _sameOrigin {
    if (!kIsWeb) return null;
    final base = Uri.base;
    if (!base.scheme.startsWith('http') || base.host.isEmpty) return null;
    final secure = base.scheme == 'https';
    return Uri(
      scheme: secure ? 'wss' : 'ws',
      host: base.host,
      port: base.hasPort ? base.port : (secure ? 443 : 80),
      path: webSocketPath,
    );
  }

  @override
  void initState() {
    super.initState();
    Prefs.loadName().then((name) {
      if (mounted && _name.text.isEmpty) _name.text = name;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _cleanName() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Pick a name first.');
      return null;
    }
    Prefs.saveName(name);
    return name;
  }

  Future<void> _host() async {
    final name = _cleanName();
    if (name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final host = LanHost();
    final session = GameSession();
    try {
      await host.start(gameName: "$name's game");
      final ok = await session.connect(host.localSocketUri, name);
      if (!ok) throw StateError(session.failure ?? 'Could not start.');
    } catch (error) {
      await host.stop();
      session.dispose();
      if (mounted) setState(() => _error = '$error');
      setState(() => _busy = false);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GamePage(session: session, host: host),
      ),
    );
  }

  Future<void> _joinUri(Uri uri) async {
    final name = _cleanName();
    if (name == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = GameSession();
    final ok = await session.connect(uri, name);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = session.failure;
    });
    if (!ok) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GamePage(session: session)),
    );
  }

  Future<void> _browse() async {
    final name = _cleanName();
    if (name == null) return;
    final uri = await Navigator.of(context).push<Uri>(
      MaterialPageRoute(builder: (_) => const JoinPage()),
    );
    if (uri != null) await _joinUri(uri);
  }

  @override
  Widget build(BuildContext context) {
    final sameOrigin = _sameOrigin;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Text(
                  'Matching Cards',
                  style: Theme.of(context).textTheme.displaySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'A party game for three or more, on your own network.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _name,
                  maxLength: 20,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (sameOrigin != null) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _joinUri(sameOrigin),
                    icon: const Icon(Icons.login),
                    label: const Text('Join this game'),
                  ),
                  const SizedBox(height: 12),
                ],
                if (LanHost.supported) ...[
                  FilledButton.icon(
                    onPressed: _busy ? null : _host,
                    icon: const Icon(Icons.add),
                    label: const Text('Host a game'),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _busy ? null : _browse,
                  icon: const Icon(Icons.wifi_find),
                  label: Text(
                    sameOrigin != null ? 'Join another game' : 'Join a game',
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
