import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:customer_app/main.dart';

void main() {
  testWidgets('Splash shows RidDev branding', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CustomerApp()),
    );
    expect(find.text('RidDev'), findsOneWidget);
  });
}
