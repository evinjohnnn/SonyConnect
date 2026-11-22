import 'package:flutter_test/flutter_test.dart';

import 'package:sony_companion/main.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const SonyCompanionApp());
    expect(find.byType(SonyCompanionApp), findsOneWidget);
  });
}
