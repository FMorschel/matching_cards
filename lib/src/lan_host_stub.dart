/// Browsers cannot listen for connections, so they cannot host a game.
class LanHost {
  static bool get supported => false;

  bool get isRunning => false;
  bool get isOpen => false;
  bool get webClientBundled => false;
  int get port => 0;
  List<String> get addresses => const [];
  Uri get localSocketUri => throw UnsupportedError('Hosting needs a native app.');

  Future<void> start({required String gameName}) =>
      throw UnsupportedError('Hosting needs a native app.');
  Future<void> setOpen(bool open) async {}
  Future<void> stop() async {}
}
