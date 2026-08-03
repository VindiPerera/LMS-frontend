import 'package:flutter_test/flutter_test.dart';

import 'package:hellotalk_clone/main.dart';

void main() {
  testWidgets('App launches and shows bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const HelloTalkCloneApp());
    await tester.pumpAndSettle();

    expect(find.text('HelloTalk'), findsWidgets);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Moments'), findsWidgets);
    expect(find.text('Voiceroom'), findsWidgets);
    expect(find.text('Me'), findsOneWidget);
  });
}
