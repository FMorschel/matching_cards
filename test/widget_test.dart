import 'package:flutter_test/flutter_test.dart';
import 'package:matching_cards/main.dart';

void main() {
  testWidgets('home screen offers to join a game', (tester) async {
    await tester.pumpWidget(const MatchingCardsApp());
    await tester.pump();
    expect(find.text('Matching Cards'), findsOneWidget);
    expect(find.text('Join a game'), findsOneWidget);
  });
}
