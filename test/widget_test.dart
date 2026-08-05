import 'package:flutter_test/flutter_test.dart';

import 'package:facetalk_clone/main.dart';

void main() {
  testWidgets('App launches and shows the splash screen with FaceTalk branding', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceTalkApp());
    await tester.pump();

    expect(find.text('FaceTalk'), findsWidgets);
    expect(find.text('Talk, learn and grow together'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
  });

  testWidgets('Tapping Next on splash navigates to the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceTalkApp());
    await tester.pump();

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
