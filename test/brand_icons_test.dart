import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facetalk_clone/widgets/brand_icons.dart';

void main() {
  testWidgets('BrandIcon renders whatsapp, telegram, messenger without error', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              BrandIcon.whatsapp(size: 26, color: Colors.white),
              BrandIcon.telegram(size: 26, color: Colors.white),
              BrandIcon.messenger(size: 26, color: Colors.white),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(BrandIcon), findsNWidgets(3));
  });
}
