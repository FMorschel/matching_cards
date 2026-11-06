# Matching Cards

A Cards Against Humanity style party game for three or more players, built
with Flutter. One player hosts, others join over the local network — from the
app or straight from a browser.

> **Status:** written without access to a Flutter or Dart SDK, so nothing here
> has been compiled or run yet. Expect a few small fixes on first build.
> Start with the tests (see below).

## How to play

Each round one player is the **Card Czar**. A prompt appears with a blank
(`_____`); everyone else plays the funniest answer from their hand (prompts with
two blanks need two answers). The Czar reads the anonymous answers and picks a
winner, who scores a point. The Czar rotates; first to the target score wins
(default 5). Thirty categories of cards live in `assets/decks/cards.json`.

## Hosting and joining

* **Host a game** (native app) creates the game on your device. Only you can
  see it until you press **"I want others to join in"**. Then the game is
  announced on the LAN (UDP broadcast) and others can join.
* **Join a game** (native app) lists announced games, or takes a typed address.
* **Browsers** cannot host or receive broadcasts. They join by opening the
  host's address (shown in the lobby, with a QR code), which serves the web
  client, and pressing **Join this game**.
* Disconnected players keep their seat and hand and can rejoin; if too few
  players remain the game pauses.

## Setup

Platform folders are not committed. Generate them once:

```sh
flutter create --platforms=web,windows,android,linux,macos .
flutter pub get
```

Then allow networking:

* **Android** – in `AndroidManifest.xml` add
  `<uses-permission android:name="android.permission.INTERNET"/>` and
  `android:usesCleartextTraffic="true"` on `<application>`.
* **macOS** – add `com.apple.security.network.server` and
  `com.apple.security.network.client` (true) to both entitlements files.
* **iOS** – add `NSLocalNetworkUsageDescription` to `Info.plist`.
* **Windows** – accept the firewall prompt the first time you host.

## Letting browsers join an in-app host

```sh
dart run tool/bundle_web.dart   # builds web, copies it into assets/web_client/
flutter run -d windows          # or any native target
```

Note: the web build may fetch fonts from a CDN; offline browsers fall back to
system fonts.

## Headless host

```sh
flutter build web --release --no-web-resources-cdn
dart run packages/matching_cards_core/bin/server.dart --web build/web
```

## Tests

```sh
cd packages/matching_cards_core && dart pub get && dart test
cd ../.. && flutter test
```

## Layout

* `packages/matching_cards_core` – pure Dart: decks, rules engine, protocol,
  WebSocket/HTTP server, LAN discovery, headless server. Web-safe entry point
  `matching_cards_core.dart`; `server.dart` needs `dart:io`.
* `lib/` – the Flutter app (session, pages, widgets).
* `tool/bundle_web.dart` – web client bundling.

The protocol (JSON over WebSocket at `/ws`) is documented at the top of
`packages/matching_cards_core/lib/src/protocol.dart`.
